package indexes

import (
	"context"
	"log"
	"sort"
	"strings"

	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type CollectionIndex struct {
	Name      string      `bson:"name"`
	Namespace string      `bson:"ns"`
	V         int         `bson:"v"`
	Key       primitive.D `bson:"key"`
}

func (di CollectionIndex) ComparableKey() string {
	str := ""
	for _, elem := range di.Key {
		sign := "+"
		if elem.Value.(int32) < 0 {
			sign = "-"
		}
		str += sign + elem.Key
	}
	return str
}

type IndexKey []primitive.E

func (di IndexKey) String() string {
	str := ""
	for _, elem := range di {
		sign := "+"
		if elem.Value.(int32) < 0 {
			sign = "-"
		}
		str += sign + elem.Key + " "
	}

	return str
}

type DuplicateIndex struct {
	Name          string
	Key           IndexKey
	ContainerName string
	ContainerKey  IndexKey
}

func FindDuplicatedIndexes(ctx context.Context, client *mongo.Client, database, collection string) ([]DuplicateIndex, error) {
	di := []DuplicateIndex{}

	cursor, err := client.Database(database).Collection(collection).Indexes().List(ctx, nil)
	if err != nil {
		return nil, err
	}

	var results []CollectionIndex
	if err = cursor.All(context.TODO(), &results); err != nil {
		log.Fatal(err)
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].ComparableKey() < results[j].ComparableKey()
	})

	for i := 0; i < len(results)-1; i++ {
		for j := i + 1; j < len(results); j++ {
			if strings.HasPrefix(results[j].ComparableKey(), results[i].ComparableKey()) {
				idx := DuplicateIndex{
					Name:          results[i].Name,
					Key:           make([]primitive.E, len(results[i].Key)),
					ContainerName: results[j].Name,
					ContainerKey:  make([]primitive.E, len(results[j].Key)),
				}
				copy(idx.Key, results[i].Key)
				copy(idx.ContainerKey, results[j].Key)
				di = append(di, idx)
			}
		}
	}

	return di, nil
}
