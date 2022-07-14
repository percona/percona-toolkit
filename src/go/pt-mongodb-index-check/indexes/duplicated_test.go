package indexes

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/AlekSi/pointer"
	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gopkg.in/mgo.v2/bson"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
)

func TestDuplicateIndexes(t *testing.T) {
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

	_, err = database.Collection(collname).InsertOne(ctx, bson.M{"f1": 1, "f2": "2", "f3": "a", "f4": "c"})
	assert.NoError(t, err)

	testCases := []primitive.D{
		{{"f1", 1}, {"f2", -1}, {"f3", 1}, {"f4", 1}},
		{{"f1", 1}, {"f2", -1}, {"f3", 1}, {"f4", 1}}, // this will throw a duplicate index error
		{{"f1", 1}, {"f2", -1}, {"f3", 1}},
		{{"f1", 1}, {"f2", -1}},
		{{"f3", -1}},
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
	/*
	 At this point we have 5 indexes: _id: (MongoDB's default), idx_00, idx_02, idx_03, idx_04.
	 idx_01 wasn't created since it duplicates idx_00 and errCount=1.
	*/

	assert.Equal(t, 1, errCount)

	want := []Duplicate{
		{
			Name:      "idx_03",
			Namespace: "test_db.test_col",
			Key: IndexKey{
				{Key: "f1", Value: int32(1)},
				{Key: "f2", Value: int32(-1)},
			},
			ContainerName: "idx_02",
			ContainerKey: IndexKey{
				{Key: "f1", Value: int32(1)},
				{Key: "f2", Value: int32(-1)},
				{Key: "f3", Value: int32(1)},
			},
		},
		{
			Name:      "idx_03",
			Namespace: "test_db.test_col",
			Key: IndexKey{
				{Key: "f1", Value: int32(1)},
				{Key: "f2", Value: int32(-1)},
			},
			ContainerName: "idx_00",
			ContainerKey: IndexKey{
				{Key: "f1", Value: int32(1)},
				{Key: "f2", Value: int32(-1)},
				{Key: "f3", Value: int32(1)},
				{Key: "f4", Value: int32(1)},
			},
		},
		{
			Name:      "idx_02",
			Namespace: "test_db.test_col",
			Key: IndexKey{
				{Key: "f1", Value: int32(1)},
				{Key: "f2", Value: int32(-1)},
				{Key: "f3", Value: int32(1)},
			},
			ContainerName: "idx_00",
			ContainerKey: IndexKey{
				{Key: "f1", Value: int32(1)},
				{Key: "f2", Value: int32(-1)},
				{Key: "f3", Value: int32(1)},
				{Key: "f4", Value: int32(1)},
			},
		},
	}

	di, err := FindDuplicated(ctx, client, dbname, collname)
	assert.NoError(t, err)
	assert.Equal(t, want, di)
}
