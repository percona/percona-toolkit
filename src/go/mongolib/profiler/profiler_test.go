package profiler

import (
	"context"
	"fmt"
	"log"
	"os"
	"testing"
	"time"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const (
	samples = "/src/go/tests/"
)

type testVars struct {
	RootPath string
}

var vars testVars

func parseDate(dateStr string) time.Time {
	date, _ := time.Parse(time.RFC3339Nano, dateStr)
	return date
}

func TestMain(m *testing.M) {
	var err error
	if vars.RootPath, err = tutil.RootPath(); err != nil {
		log.Printf("cannot get root path: %s", err.Error())
		os.Exit(1)
	}
	os.Exit(m.Run())
}

func TestRegularIterator(t *testing.T) {
	uri := fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard1PrimaryPort)
	client, err := mongo.NewClient(options.Client().ApplyURI(uri))
	if err != nil {
		t.Fatalf("Cannot create a new MongoDB client: %s", err)
	}

	ctx := context.Background()

	if err := client.Connect(ctx); err != nil {
		t.Fatalf("Cannot connect to MongoDB: %s", err)
	}

	database := "test"
	// Disable the profiler and drop the db. This should also remove the system.profile collection
	// so the stats should be re-initialized
	res := client.Database("admin").RunCommand(ctx, primitive.M{"profile": 0})
	if res.Err() != nil {
		t.Fatalf("Cannot enable profiler: %s", res.Err())
	}
	err = client.Database(database).Drop(ctx)
	assert.NoError(t, err)

	// re-enable the profiler
	res = client.Database("admin").RunCommand(ctx, primitive.D{{"profile", 2}, {"slowms", 2}})
	if res.Err() != nil {
		t.Fatalf("Cannot enable profiler: %s", res.Err())
	}

	// run some queries to have something to profile
	count := 1000
	for j := 0; j < count; j++ {
		_, err := client.Database("test").Collection("testc").InsertOne(ctx, primitive.M{"number": j})
		assert.NoError(t, err)
		time.Sleep(20 * time.Millisecond)
	}

	cursor, err := client.Database(database).Collection("system.profile").Find(ctx, primitive.M{})
	if err != nil {
		panic(err)
	}
	filters := []filter.Filter{}

	fp := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters())
	s := stats.New(fp)
	prof := NewProfiler(cursor, filters, nil, s)
	prof.Start(ctx)

	queries := <-prof.QueriesChan()
	found := false
	valid := false

	for _, query := range queries {
		if query.Namespace == "test.testc" && query.Operation == "INSERT" {
			found = true
			if query.Fingerprint == "INSERT testc" && query.Count == count {
				valid = true
			}
			break
		}
	}

	if !found {
		t.Errorf("Insert query was not found")
	}
	if !valid {
		t.Errorf("Query stats are not valid")
	}
}
