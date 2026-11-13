// This program is copyright 2022-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package indexes

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/AlekSi/pointer"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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
		{{Key: "f1", Value: 1}, {Key: "f2", Value: -1}, {Key: "f3", Value: 1}, {Key: "f4", Value: 1}},
		{{Key: "f1", Value: 1}, {Key: "f2", Value: -1}, {Key: "f3", Value: 1}, {Key: "f4", Value: 1}}, // this will throw a duplicate index error
		{{Key: "f1", Value: 1}, {Key: "f2", Value: -1}, {Key: "f3", Value: 1}},
		{{Key: "f1", Value: 1}, {Key: "f2", Value: -1}},
		{{Key: "f3", Value: -1}},
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

	di, _, err := FindDuplicated(ctx, client, dbname, collname)
	assert.NoError(t, err)
	assert.Equal(t, want, di)
}

func TestDuplicatePairsComparesWholeFieldNames(t *testing.T) {
	got, _ := duplicatePairs("db.c", []collectionIndex{
		{Name: "a_1", Key: primitive.D{{Key: "a", Value: int32(1)}}},
		{Name: "ab_1_x_1", Key: primitive.D{{Key: "ab", Value: int32(1)}, {Key: "x", Value: int32(1)}}},
		{Name: "a_1_b_1", Key: primitive.D{{Key: "a", Value: int32(1)}, {Key: "b", Value: int32(1)}}},
	})

	require.Len(t, got, 1)
	assert.Equal(t, "a_1", got[0].Name)
	assert.Equal(t, "a_1_b_1", got[0].ContainerName)
}

func TestDuplicatePairsMarksConstraintPrefixes(t *testing.T) {
	got, _ := duplicatePairs("db.c", []collectionIndex{
		{Name: "u_1", Key: primitive.D{{Key: "u", Value: int32(1)}}, Unique: true},
		{Name: "u_1_b_1", Key: primitive.D{{Key: "u", Value: int32(1)}, {Key: "b", Value: int32(1)}}, Unique: true},
		{Name: "t_1", Key: primitive.D{{Key: "t", Value: int32(1)}}, ExpireAfterSeconds: int32(60)},
		{Name: "t_1_b_1", Key: primitive.D{{Key: "t", Value: int32(1)}, {Key: "b", Value: int32(1)}}},
		{Name: "p_1", Key: primitive.D{{Key: "p", Value: int32(1)}}},
		{Name: "p_1_b_1", Key: primitive.D{{Key: "p", Value: int32(1)}, {Key: "b", Value: int32(1)}}},
	})

	byName := map[string]Duplicate{}
	for _, d := range got {
		byName[d.Name] = d
	}

	require.Len(t, byName, 3)
	assert.Equal(t, "unique", byName["u_1"].Constraint)
	assert.Contains(t, byName["u_1"].Warning, "loses the unique constraint")
	assert.Equal(t, "TTL", byName["t_1"].Constraint)
	assert.Contains(t, byName["t_1"].Warning, "stops document expiry")
	assert.Empty(t, byName["p_1"].Constraint)
	assert.Empty(t, byName["p_1"].Warning)
}

func TestDuplicatePairsListsSkippedPairs(t *testing.T) {
	dups, skipped := duplicatePairs("db.people", []collectionIndex{
		{Name: "name_1", Key: primitive.D{{Key: "name", Value: int32(1)}}, PartialFilter: primitive.M{"age": primitive.M{"$gt": 50}}},
		{
			Name: "name_1_surname_1", Key: primitive.D{{Key: "name", Value: int32(1)}, {Key: "surname", Value: int32(1)}},
			PartialFilter: primitive.M{"age": primitive.M{"$lte": 30}},
		},
		{Name: "s_1", Key: primitive.D{{Key: "s", Value: int32(1)}}, Sparse: true},
		{Name: "s_1_x_1", Key: primitive.D{{Key: "s", Value: int32(1)}, {Key: "x", Value: int32(1)}}},
	})

	assert.Empty(t, dups)
	assert.Equal(t, []SkippedDuplicate{
		{Namespace: "db.people", Name: "name_1", ContainerName: "name_1_surname_1", Reason: "partialFilterExpression differs"},
		{Namespace: "db.people", Name: "s_1", ContainerName: "s_1_x_1", Reason: "sparse differs"},
	}, skipped)
}

func TestDuplicatePairsSkipsUnusableContainers(t *testing.T) {
	dups, skipped := duplicatePairs("db.c", []collectionIndex{
		{Name: "s_1", Key: primitive.D{{Key: "s", Value: int32(1)}}},
		{Name: "s_1_body_text", Key: primitive.D{{Key: "s", Value: int32(1)}, {Key: "_fts", Value: "text"}, {Key: "_ftsx", Value: int32(1)}}},
		{Name: "g_1", Key: primitive.D{{Key: "g", Value: int32(1)}}},
		{Name: "g_1_loc_2dsphere", Key: primitive.D{{Key: "g", Value: int32(1)}, {Key: "loc", Value: "2dsphere"}}},
		{Name: "h_1", Key: primitive.D{{Key: "h", Value: int32(1)}}},
		{Name: "h_1_x_1", Key: primitive.D{{Key: "h", Value: int32(1)}, {Key: "x", Value: int32(1)}}, Hidden: true},
		{Name: "p_1", Key: primitive.D{{Key: "p", Value: int32(1)}}},
		{Name: "p_geoHaystack_t_1", Key: primitive.D{{Key: "p", Value: "geoHaystack"}, {Key: "t", Value: int32(1)}}},
		{Name: "loc_2dsphere", Key: primitive.D{{Key: "loc", Value: "2dsphere"}}},
		{Name: "loc_2dsphere_b_1", Key: primitive.D{{Key: "loc", Value: "2dsphere"}, {Key: "b", Value: int32(1)}}},
	})

	require.Len(t, dups, 1)
	assert.Equal(t, "loc_2dsphere", dups[0].Name)

	reasons := map[string]string{}
	for _, s := range skipped {
		reasons[s.Name] = s.Reason
	}
	assert.Equal(t, map[string]string{
		"s_1": "the container is a text index",
		"g_1": "the container is a geospatial index",
		"h_1": "the container is hidden",
	}, reasons)
}

func TestFindDuplicatedPrefixRules(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := tu.TestClient(ctx, tu.MongoDBStandalonePort)
	require.NoError(t, err)

	defer client.Disconnect(ctx) //nolint:errcheck

	const dbname = "test_prefix_rules"

	db := client.Database(dbname)
	require.NoError(t, db.Drop(ctx))

	defer db.Drop(ctx) //nolint:errcheck

	create := func(coll string, models ...mongo.IndexModel) {
		t.Helper()

		_, err := db.Collection(coll).Indexes().CreateMany(ctx, models)
		require.NoError(t, err)
	}

	ab := primitive.D{{Key: "a", Value: 1}, {Key: "b", Value: 1}}
	a := primitive.D{{Key: "a", Value: 1}}

	create("uq",
		mongo.IndexModel{Keys: a, Options: options.Index().SetUnique(true)},
		mongo.IndexModel{Keys: ab, Options: options.Index().SetUnique(true)})
	create("ttl",
		mongo.IndexModel{Keys: a, Options: options.Index().SetExpireAfterSeconds(60)},
		mongo.IndexModel{Keys: ab})
	create("names",
		mongo.IndexModel{Keys: a},
		mongo.IndexModel{Keys: primitive.D{{Key: "ab", Value: 1}, {Key: "x", Value: 1}}})
	create("people",
		mongo.IndexModel{
			Keys:    primitive.D{{Key: "name", Value: 1}},
			Options: options.Index().SetPartialFilterExpression(primitive.M{"age": primitive.M{"$gt": 50}}),
		},
		mongo.IndexModel{
			Keys:    primitive.D{{Key: "name", Value: 1}, {Key: "surname", Value: 1}},
			Options: options.Index().SetPartialFilterExpression(primitive.M{"age": primitive.M{"$lte": 30}}),
		})
	create("text",
		mongo.IndexModel{Keys: a},
		mongo.IndexModel{Keys: primitive.D{{Key: "a", Value: 1}, {Key: "body", Value: "text"}}})
	create("geo",
		mongo.IndexModel{Keys: a},
		mongo.IndexModel{Keys: primitive.D{{Key: "a", Value: 1}, {Key: "loc", Value: "2dsphere"}}})

	dups, _, err := FindDuplicated(ctx, client, dbname, "uq")
	require.NoError(t, err)
	require.Len(t, dups, 1)
	assert.Equal(t, "unique", dups[0].Constraint)

	dups, _, err = FindDuplicated(ctx, client, dbname, "ttl")
	require.NoError(t, err)
	require.Len(t, dups, 1)
	assert.Equal(t, "TTL", dups[0].Constraint)

	dups, _, err = FindDuplicated(ctx, client, dbname, "names")
	require.NoError(t, err)
	assert.Empty(t, dups)

	dups, skipped, err := FindDuplicated(ctx, client, dbname, "people")
	require.NoError(t, err)
	assert.Empty(t, dups)
	assert.Equal(t, []SkippedDuplicate{{
		Namespace: dbname + ".people", Name: "name_1", ContainerName: "name_1_surname_1", Reason: "partialFilterExpression differs",
	}}, skipped)

	dups, skipped, err = FindDuplicated(ctx, client, dbname, "text")
	require.NoError(t, err)
	assert.Empty(t, dups)
	require.Len(t, skipped, 1)
	assert.Equal(t, "the container is a text index", skipped[0].Reason)

	dups, skipped, err = FindDuplicated(ctx, client, dbname, "geo")
	require.NoError(t, err)
	assert.Empty(t, dups)
	require.Len(t, skipped, 1)
	assert.Equal(t, "the container is a geospatial index", skipped[0].Reason)
}
