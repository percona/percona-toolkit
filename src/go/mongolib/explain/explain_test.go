package explain

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"
	"testing"

	"github.com/Masterminds/semver"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"
	"gopkg.in/mgo.v2/bson"
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

	dialer := pmgo.NewDialer()
	dialInfo, err := pmgo.ParseURL("")
	if err != nil {
		t.Fatalf("cannot parse URL: %s", err)
	}

	session, err := dialer.DialWithInfo(dialInfo)
	if err != nil {
		t.Fatalf("cannot dial to MongoDB: %s", err)
	}
	defer session.Close()

	dir := vars.RootPath + samples + "/doc/out/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	bi, err := session.BuildInfo()
	if err != nil {
		t.Fatalf("cannot get BuildInfo: %s", err)
	}

	versions := []string{
		"2.6.12",
		"3.0.15",
		"3.2.19",
		"3.4.12",
		"3.6.2",
	}

	samples := map[string]string{
		"aggregate":        "Cannot explain cmd: aggregate",
		"count":            "<nil>",
		"count_with_query": "<nil>",
		"delete":           "<nil>",
		"delete_all":       "<nil>",
		"distinct":         "<nil>",
		"find_empty":       "<nil>",
		"find":             "<nil>",
		"find_with_sort":   "<nil>",
		"find_andrii":      "<nil>",
		"findandmodify":    "<nil>",
		"geonear":          "Cannot explain cmd: geoNear",
		"getmore":          "<nil>",
		"group":            "<nil>",
		"insert":           "Cannot explain cmd: insert",
		"mapreduce":        "Cannot explain cmd: mapReduce",
		"update":           "<nil>",
		"explain":          "Cannot explain cmd: explain",
		"eval":             "Cannot explain cmd: eval",
	}

	expectError := map[string]string{}

	// For versions < 3.0 explain is not supported
	if ok, _ := Constraint("< 3.0", bi.Version); ok {
		for _, v := range versions {
			for sample := range samples {
				expectError[sample+"_"+v] = "no such cmd: explain"
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
				expectError["getmore_"+v] = "Explain failed due to unknown command: getmore"
			}
		}

		// For versions >= 3.0, < 3.4 trying to explain "insert" returns different error
		if ok, _ := Constraint(">= 3.0, < 3.4", bi.Version); ok {
			for _, v := range versions {
				expectError["insert_"+v] = "Only update and delete write ops can be explained"
			}
		}

		// Explaining `distinct` and `findAndModify` was introduced in MongoDB 3.2
		if ok, _ := Constraint(">= 3.0, < 3.2", bi.Version); ok {
			for _, v := range versions {
				expectError["distinct_"+v] = "Cannot explain cmd: distinct"
				expectError["findandmodify_"+v] = "Cannot explain cmd: findAndModify"
			}
		}
	}

	ex := New(session)
	for _, file := range files {
		t.Run(file.Name(), func(t *testing.T) {
			eq := proto.ExampleQuery{}
			err := tutil.LoadBson(dir+file.Name(), &eq)
			if err != nil {
				t.Fatalf("cannot load sample %s: %s", dir+file.Name(), err)
			}
			query, err := bson.MarshalJSON(eq)
			if err != nil {
				t.Fatalf("cannot marshal json %s: %s", dir+file.Name(), err)
			}
			got, err := ex.Explain("", query)
			expectErrMsg := expectError[file.Name()]
			gotErrMsg := fmt.Sprintf("%v", err)
			if gotErrMsg != expectErrMsg {
				t.Fatalf("explain error should be '%s' but was '%s'", expectErrMsg, gotErrMsg)
			}

			if err == nil {
				result := proto.BsonD{}
				err = bson.UnmarshalJSON(got, &result)
				if err != nil {
					t.Fatalf("cannot unmarshal json explain result: %s", err)
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
