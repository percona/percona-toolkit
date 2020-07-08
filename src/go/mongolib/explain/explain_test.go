package explain

import (
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/Masterminds/semver"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

const (
	samples = "/src/go/tests/"
)

type testVars struct {
	RootPath string
}

var vars testVars

func TestMain(m *testing.M) {
	var err error
	if vars.RootPath, err = tutil.RootPath(); err != nil {
		log.Printf("cannot get root path: %s", err.Error())
		os.Exit(1)
	}
	os.Exit(m.Run())
}

func TestExplain(t *testing.T) {
	t.Parallel()

	uri := fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBMongosPort)
	client, err := mongo.NewClient(options.Client().ApplyURI(uri))
	if err != nil {
		t.Fatalf("cannot get a new MongoDB client: %s", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	err = client.Connect(ctx)
	if err != nil {
		t.Fatalf("Cannot connect to MongoDB: %s", err)
	}

	dir := vars.RootPath + samples + "/doc/out/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	res := client.Database("admin").RunCommand(ctx, primitive.M{"buildInfo": 1})
	if res.Err() != nil {
		t.Fatalf("Cannot get buildInfo: %s", err)
	}
	bi := proto.BuildInfo{}
	if err := res.Decode(&bi); err != nil {
		t.Fatalf("Cannot decode buildInfo response: %s", err)
	}

	versions := []string{
		"2.6.12",
		"3.0.15",
		"3.2.19",
		"3.4.12",
		"3.6.2",
	}

	samples := map[string]bool{
		"aggregate":        false,
		"count":            false,
		"count_with_query": false,
		"delete":           false,
		"delete_all":       false,
		"distinct":         false,
		"find_empty":       true,
		"find":             false,
		"find_with_sort":   false,
		"find_andrii":      false,
		"findandmodify":    false,
		"geonear":          true,
		"getmore":          false,
		"group":            false,
		"insert":           true,
		"mapreduce":        true,
		"update":           false,
		"explain":          true,
		"eval":             true,
	}

	expectError := map[string]bool{}

	// For versions < 3.0 explain is not supported
	if ok, _ := Constraint("< 3.0", bi.Version); ok {
		for _, v := range versions {
			for sample := range samples {
				expectError[sample+"_"+v] = true
			}
		}
	} else {
		for _, v := range versions {
			for sample, msg := range samples {
				expectError[sample+"_"+v] = msg
			}
		}

		for _, v := range versions {
			// For versions < 3.4 parsing "getmore" is not supported and returns error
			if ok, _ := Constraint("< 3.4", v); ok {
				expectError["getmore_"+v] = true
			}
		}

		for _, v := range versions {
			// For versions < 3.4 parsing "getmore" is not supported and returns error
			if ok, _ := Constraint(">= 2.4, <= 2.6", v); ok {
				expectError["find_empty_"+v] = false
			}
			if ok, _ := Constraint(">= 3.2", v); ok {
				expectError["find_empty_"+v] = false
			}
		}

		// For versions >= 3.0, < 3.4 trying to explain "insert" returns different error
		if ok, _ := Constraint(">= 3.0, < 3.4", bi.Version); ok {
			for _, v := range versions {
				expectError["insert_"+v] = true
			}
		}

		// Explaining `distinct` and `findAndModify` was introduced in MongoDB 3.2
		if ok, _ := Constraint(">= 3.0, < 3.2", bi.Version); ok {
			for _, v := range versions {
				expectError["distinct_"+v] = true
				expectError["findandmodify_"+v] = true
			}
		}
	}

	ex := New(ctx, client)
	for _, file := range files {
		t.Run(file.Name(), func(t *testing.T) {
			query, err := ioutil.ReadFile(dir + file.Name())
			assert.NoError(t, err)

			got, err := ex.Run("", query)
			idx := strings.TrimSuffix(file.Name(), ".new.bson")
			expectErrMsg := expectError[idx]
			if (err != nil) != expectErrMsg {
				t.Errorf("explain error for %q \n %s\nshould be '%v' but was '%v'", string(query), file.Name(), expectErrMsg, err)
			}

			if err == nil {
				result := proto.BsonD{}
				err = bson.UnmarshalExtJSON(got, true, &result)
				if err != nil {
					t.Errorf("cannot unmarshal json explain result: %s", err)
				}
			}
		})
	}
}

func Constraint(constraint, version string) (bool, error) {
	// Drop everything after first dash.
	// Version with dash is considered a pre-release
	// but some MongoDB builds add additional information after dash
	// even though it's not considered a pre-release but a release.
	s := strings.SplitN(version, "-", 2)
	version = s[0]

	// Create new version
	v, err := semver.NewVersion(version)
	if err != nil {
		return false, err
	}

	// Check if version matches constraint
	constraints, err := semver.NewConstraint(constraint)
	if err != nil {
		return false, err
	}
	return constraints.Check(v), nil
}
