package indexes

import (
	"context"

	"github.com/pkg/errors"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

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
	Name string      `bson:"name"`
	Key  primitive.D `bson:"key"`
	Host string      `bson:"host"`
}

// FindUnusedIndexes returns a list of unused indexes for the given database and collection.
func FindUnusedIndexes(ctx context.Context, client *mongo.Client, database, collection string) ([]IndexStat, error) {
	aggregation := mongo.Pipeline{
		{{Key: "$indexStats", Value: primitive.M{}}},
		{{Key: "$match", Value: primitive.M{"accesses.ops": 0}}},
	}

	cursor, err := client.Database(database).Collection(collection).Aggregate(ctx, aggregation)
	if err != nil {
		return nil, errors.Wrap(err, "cannot run $indexStats for unused indexes")
	}

	var stats []IndexStat
	if err = cursor.All(ctx, &stats); err != nil {
		return nil, errors.Wrap(err, "cannot get $indexStats for unused indexes")
	}

	return stats, nil
}
