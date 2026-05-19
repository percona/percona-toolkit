package indexes

import (
	"context"
	"strings"

	"github.com/pkg/errors"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

var systemDBs = []string{"admin", "config", "local", "system.profile"} //nolint:gochecknoglobals
// IndexStat hold an index usage statistics.
type IndexStat struct {
	Accesses struct {
		Ops   int64              `bson:"ops"`
		Since primitive.DateTime `bson:"since"`
	} `bson:"accesses"`
	Spec struct {
		Name      string      `bson:"name"`
		Namespace string      `bson:"ns"`
		V         int32       `bson:"v"`
		Key       primitive.D `bson:"key"`
	} `bson:"spec"`
	Name       string      `bson:"name"`
	Key        primitive.D `bson:"key"`
	Host       string      `bson:"host"`
	ShardCount int         `bson:"-"`
}

// NormalizeIndexStat fills top-level name/key from spec when the driver or
// mongos omits them on $indexStats documents, so aggregation and lookups
// group by the correct index name.
func NormalizeIndexStat(s *IndexStat) {
	if s.Name == "" && s.Spec.Name != "" {
		s.Name = s.Spec.Name
	}
	if len(s.Key) == 0 && len(s.Spec.Key) > 0 {
		s.Key = s.Spec.Key
	}
}

func in(search string, items []string) bool {
	for _, item := range items {
		if search == item {
			return true
		}
	}
	return false
}

// IsSystemDB returns true if the database is a MongoDB system database
// that should be skipped during index analysis.
func IsSystemDB(database string) bool {
	return in(database, systemDBs)
}

// IsSystemCollection returns true for MongoDB internal collections whose
// names start with "system." (e.g. system.profile, system.js). These should
// be skipped alongside system databases (admin, config, local).
func IsSystemCollection(collection string) bool {
	return strings.HasPrefix(collection, "system.")
}

// FindUnusedIndexes returns a list of unused indexes for the given database and collection.
func FindUnused(ctx context.Context, client *mongo.Client, database, collection string) ([]IndexStat, error) {
	aggregation := mongo.Pipeline{
		{{Key: "$indexStats", Value: primitive.M{}}},
	}

	if in(database, systemDBs) {
		return nil, nil
	}

	cursor, err := client.Database(database).Collection(collection).Aggregate(ctx, aggregation)
	if err != nil {
		return nil, errors.Wrap(err, "cannot run $indexStats for unused indexes")
	}

	var stats []IndexStat
	if err = cursor.All(ctx, &stats); err != nil {
		return nil, errors.Wrap(err, "cannot get $indexStats for unused indexes")
	}
	for i := range stats {
		NormalizeIndexStat(&stats[i])
	}
	stats = AggregateShardStats(stats)

	var out []IndexStat
	for _, s := range stats {
		if s.Name == "_id_" {
			continue
		}
		if s.Accesses.Ops != 0 {
			continue
		}
		out = append(out, s)
	}
	return out, nil
}
