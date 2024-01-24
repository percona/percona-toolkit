package indexes

import (
	"context"
	"log"
	"sort"
	"strings"

	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type collectionIndex struct {
	Name      string      `bson:"name"`
	Namespace string      `bson:"ns"`
	V         int         `bson:"v"`
	Key       primitive.D `bson:"key"`
}

func (di collectionIndex) ComparableKey() string {
	str := ""
	for _, elem := range di.Key {
		str += sign(elem) + elem.Key
	}
	return str
}

func sign(elem primitive.E) string {
	sign := "+"
	switch elem.Value.(type) {
	case int32: // internal MongoDB indexes like _id_ or lastUsed have the sign field as int32.
		if elem.Value.(int32) < 0 {
			sign = "-"
		}
	case float64: // All other indexes have the sign field as float64.
		if elem.Value.(float64) < 0 {
			sign = "-"
		}
	}
	return sign
}

// IndexKey holds the list of fields that are part of an index, along with the field order.
type IndexKey []primitive.E

// String returns the index fields as a string. The + sign means ascending on this field
// and a - sign indicates a descending order for that field.
func (di IndexKey) String() string {
	str := ""
	for _, elem := range di {
		str += sign(elem) + elem.Key + " "
	}

	return str
}

// DuplicateIndex represents a duplicated index pair.
// An index is considered as the duplicate of another one if it is it's prefix.
// Example: the index +f1-f2 is the prefix of +f1-f2+f3.
type Duplicate struct {
	Namespace     string
	Name          string
	Key           IndexKey
	ContainerName string
	ContainerKey  IndexKey
}

func FindDuplicated(ctx context.Context, client *mongo.Client, database, collection string) ([]Duplicate, error) {
	di := []Duplicate{}

	cursor, err := client.Database(database).Collection(collection).Indexes().List(ctx, nil)
	if err != nil {
		return nil, err
	}

	var results []collectionIndex
	if err = cursor.All(context.TODO(), &results); err != nil {
		log.Fatal(err)
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].ComparableKey() < results[j].ComparableKey()
	})

	for i := 0; i < len(results)-1; i++ {
		for j := i + 1; j < len(results); j++ {
			if strings.HasPrefix(results[j].ComparableKey(), results[i].ComparableKey()) {
				idx := Duplicate{
					Namespace:     database + "." + collection,
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
