package indexes

import (
	"context"
	"fmt"
	"math/rand"
	"sort"
	"testing"
	"time"

	"github.com/AlekSi/pointer"
	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gopkg.in/mgo.v2/bson"
)

func TestUnusedIndexes(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := tu.TestClient(ctx, tu.MongoDBShard1PrimaryPort)
	if err != nil {
		t.Fatalf("cannot get a new MongoDB client: %s", err)
	}

	dbname := "test_db"
	collname := "test_col"

	database := client.Database(dbname)
	database.Drop(ctx)       //nolint:errcheck
	defer database.Drop(ctx) //nolint:errcheck

	testCases := []primitive.D{
		{{"f1", 1}, {"f2", -1}, {"f3", 1}, {"f4", 1}},
		{{"f3", -1}},
		{{"f4", -1}},
	}

	errCount := 0
	for i, tc := range testCases {
		mod := mongo.IndexModel{
			Keys: tc,
			Options: &options.IndexOptions{
				Name: pointer.ToString(fmt.Sprintf("idx_%02d", i)),
			},
		}
		_, err := database.Collection(collname).Indexes().CreateOne(ctx, mod)
		if err != nil {
			errCount++
		}
	}

	for i := 0; i < 100; i++ {
		_, err = database.Collection(collname).InsertOne(ctx,
			bson.M{"f1": rand.Int63n(1000), "f2": rand.Int63n(1000), "f3": rand.Int63n(1000), "f4": rand.Int63n(1000)})
		assert.NoError(t, err)
	}

	want := []string{"_id_", "idx_00", "idx_01", "idx_02"}

	ui, err := FindUnusedIndexes(ctx, client, dbname, collname)
	assert.NoError(t, err)

	got := make([]string, 0, len(ui))
	for _, idx := range ui {
		// compare only names because the index struct has a timestamp in it and it is variable.
		got = append(got, idx.Name)
	}

	sort.Strings(got)

	assert.Equal(t, want, got)
}
