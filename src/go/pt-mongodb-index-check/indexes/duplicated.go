package indexes

import (
	"context"
	"fmt"
	"reflect"
	"sort"
	"strings"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type collectionIndex struct {
	Name          string      `bson:"name"`
	Namespace     string      `bson:"ns"`
	V             int         `bson:"v"`
	Key           primitive.D `bson:"key"`
	PartialFilter primitive.M `bson:"partialFilterExpression,omitempty"`
	Sparse        bool        `bson:"sparse,omitempty"`
	Unique        bool        `bson:"unique,omitempty"`
	Collation     primitive.M `bson:"collation,omitempty"`
}

func (di collectionIndex) ComparableKey() string {
	str := ""
	for _, elem := range di.Key {
		str += keyToken(elem)
	}
	return str
}

// keyToken produces a unique prefix token for an index key element.
// Numeric directions map to "+" or "-", while string index types
// (hashed, text, 2dsphere, 2d) use "type:" so they never collide
// with B-tree directions.
//
// MongoDB 8.x may encode the "hashed" key value as BSON Symbol (type 0x0E)
// rather than a plain BSON String (type 0x02). primitive.Symbol is a distinct
// Go named type (type Symbol string) so it does not match case string and
// requires its own branch.
func keyToken(elem primitive.E) string {
	log.Debugf("keyToken field=%q type=%T value=%v", elem.Key, elem.Value, elem.Value)
	switch v := elem.Value.(type) {
	case int32:
		if v < 0 {
			return "-" + elem.Key
		}
		return "+" + elem.Key
	case int64:
		if v < 0 {
			return "-" + elem.Key
		}
		return "+" + elem.Key
	case float64:
		if v < 0 {
			return "-" + elem.Key
		}
		return "+" + elem.Key
	case string:
		switch v {
		case "hashed", "text", "2dsphere", "2d":
			return v + ":" + elem.Key
		default:
			return "+" + elem.Key
		}
	case primitive.Symbol:
		s := string(v)
		switch s {
		case "hashed", "text", "2dsphere", "2d":
			return s + ":" + elem.Key
		default:
			return "+" + elem.Key
		}
	case []byte:
		s := string(v)
		switch s {
		case "hashed", "text", "2dsphere", "2d":
			return s + ":" + elem.Key
		default:
			return "+" + elem.Key
		}
	default:
		s := fmt.Sprint(elem.Value)
		switch s {
		case "hashed", "text", "2dsphere", "2d":
			return s + ":" + elem.Key
		default:
			return "+" + elem.Key
		}
	}
}

func sign(elem primitive.E) string {
	sign := "+"
	switch v := elem.Value.(type) {
	case int32:
		if v < 0 {
			sign = "-"
		}
	case float64:
		if v < 0 {
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
	Warning       string `json:",omitempty"`
}

// compatibleIndexProperties returns true if two indexes have compatible
// properties for a prefix-duplicate relationship. Indexes with different
// partialFilterExpression, sparse settings, or collation serve different
// purposes and should not be considered duplicates.
func compatibleIndexProperties(shorter, longer collectionIndex) bool {
	hasPartialI := len(shorter.PartialFilter) > 0
	hasPartialJ := len(longer.PartialFilter) > 0
	if hasPartialI != hasPartialJ {
		return false
	}
	if hasPartialI && hasPartialJ && !reflect.DeepEqual(shorter.PartialFilter, longer.PartialFilter) {
		return false
	}

	if shorter.Sparse != longer.Sparse {
		return false
	}

	hasCollI := len(shorter.Collation) > 0
	hasCollJ := len(longer.Collation) > 0
	if hasCollI != hasCollJ {
		return false
	}
	if hasCollI && hasCollJ && !reflect.DeepEqual(shorter.Collation, longer.Collation) {
		return false
	}

	return true
}

func FindDuplicated(ctx context.Context, client *mongo.Client, database, collection string) ([]Duplicate, error) {
	di := []Duplicate{}

	cursor, err := client.Database(database).Collection(collection).Indexes().List(ctx, nil)
	if err != nil {
		return nil, err
	}

	var results []collectionIndex
	if err = cursor.All(ctx, &results); err != nil {
		return nil, errors.Wrap(err, "cannot decode index list")
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].ComparableKey() < results[j].ComparableKey()
	})

	for i := 0; i < len(results)-1; i++ {
		if results[i].Name == "_id_" {
			continue
		}
		for j := i + 1; j < len(results); j++ {
			ki, kj := results[i].ComparableKey(), results[j].ComparableKey()
			if ki == kj {
				continue
			}
			if !strings.HasPrefix(kj, ki) {
				continue
			}
			if !compatibleIndexProperties(results[i], results[j]) {
				continue
			}

			idx := Duplicate{
				Namespace:     database + "." + collection,
				Name:          results[i].Name,
				Key:           make([]primitive.E, len(results[i].Key)),
				ContainerName: results[j].Name,
				ContainerKey:  make([]primitive.E, len(results[j].Key)),
			}
			copy(idx.Key, results[i].Key)
			copy(idx.ContainerKey, results[j].Key)

			if results[i].Unique && !results[j].Unique {
				idx.Warning = "prefix index enforces unique constraint; dropping requires the container index to also be unique"
			}

			di = append(di, idx)
		}
	}

	return di, nil
}
