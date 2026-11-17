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
	Hidden        bool        `bson:"hidden,omitempty"`

	ExpireAfterSeconds interface{} `bson:"expireAfterSeconds,omitempty"`
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
// (hashed, text, 2dsphere, 2d, geoHaystack) use "type:" so they never collide
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
		case "hashed", "text", "2dsphere", "2d", "geoHaystack":
			return v + ":" + elem.Key
		default:
			return "+" + elem.Key
		}
	case primitive.Symbol:
		s := string(v)
		switch s {
		case "hashed", "text", "2dsphere", "2d", "geoHaystack":
			return s + ":" + elem.Key
		default:
			return "+" + elem.Key
		}
	case []byte:
		s := string(v)
		switch s {
		case "hashed", "text", "2dsphere", "2d", "geoHaystack":
			return s + ":" + elem.Key
		default:
			return "+" + elem.Key
		}
	default:
		s := fmt.Sprint(elem.Value)
		switch s {
		case "hashed", "text", "2dsphere", "2d", "geoHaystack":
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
	Constraint    string `json:",omitempty"`
}

type SkippedDuplicate struct {
	Namespace     string
	Name          string
	ContainerName string
	Reason        string
}

func differingIndexOption(shorter, longer collectionIndex) string {
	hasPartialI := len(shorter.PartialFilter) > 0
	hasPartialJ := len(longer.PartialFilter) > 0
	if hasPartialI != hasPartialJ || (hasPartialI && !reflect.DeepEqual(shorter.PartialFilter, longer.PartialFilter)) {
		return "partialFilterExpression"
	}

	if shorter.Sparse != longer.Sparse {
		return "sparse"
	}

	hasCollI := len(shorter.Collation) > 0
	hasCollJ := len(longer.Collation) > 0
	if hasCollI != hasCollJ || (hasCollI && !reflect.DeepEqual(shorter.Collation, longer.Collation)) {
		return "collation"
	}

	return ""
}

func unusableContainer(prefix, container collectionIndex) string {
	if container.Hidden {
		return "the container is hidden"
	}

	for _, elem := range container.Key[len(prefix.Key):] {
		token := keyToken(elem)
		if strings.HasPrefix(token, "text:") {
			return "the container is a text index"
		}
		if strings.HasPrefix(token, "2dsphere:") || strings.HasPrefix(token, "2d:") || strings.HasPrefix(token, "geoHaystack:") {
			return "the container is a geospatial index"
		}
	}

	return ""
}

func FindDuplicated(ctx context.Context, client *mongo.Client, database, collection string) ([]Duplicate, []SkippedDuplicate, error) {
	cursor, err := client.Database(database).Collection(collection).Indexes().List(ctx, nil)
	if err != nil {
		return nil, nil, err
	}

	var results []collectionIndex
	if err = cursor.All(ctx, &results); err != nil {
		return nil, nil, errors.Wrap(err, "cannot decode index list")
	}

	dups, skipped := duplicatePairs(database+"."+collection, results)

	return dups, skipped, nil
}

func isKeyPrefix(prefix, key primitive.D) bool {
	return len(prefix) < len(key) && keyStartsWith(key, prefix)
}

func keyStartsWith(key, prefix primitive.D) bool {
	if len(prefix) == 0 || len(prefix) > len(key) {
		return false
	}

	for i := range prefix {
		if keyToken(prefix[i]) != keyToken(key[i]) {
			return false
		}
	}

	return true
}

func duplicatePairs(namespace string, results []collectionIndex) ([]Duplicate, []SkippedDuplicate) {
	di := []Duplicate{}

	var skipped []SkippedDuplicate

	sort.Slice(results, func(i, j int) bool {
		return results[i].ComparableKey() < results[j].ComparableKey()
	})

	for i := 0; i < len(results)-1; i++ {
		if results[i].Name == "_id_" {
			continue
		}
		for j := i + 1; j < len(results); j++ {
			if !isKeyPrefix(results[i].Key, results[j].Key) {
				continue
			}
			if opt := differingIndexOption(results[i], results[j]); opt != "" {
				skipped = append(skipped, SkippedDuplicate{
					Namespace:     namespace,
					Name:          results[i].Name,
					ContainerName: results[j].Name,
					Reason:        opt + " differs",
				})

				continue
			}
			if reason := unusableContainer(results[i], results[j]); reason != "" {
				skipped = append(skipped, SkippedDuplicate{
					Namespace:     namespace,
					Name:          results[i].Name,
					ContainerName: results[j].Name,
					Reason:        reason,
				})

				continue
			}

			idx := Duplicate{
				Namespace:     namespace,
				Name:          results[i].Name,
				Key:           make([]primitive.E, len(results[i].Key)),
				ContainerName: results[j].Name,
				ContainerKey:  make([]primitive.E, len(results[j].Key)),
			}
			copy(idx.Key, results[i].Key)
			copy(idx.ContainerKey, results[j].Key)

			switch {
			case results[i].Unique:
				idx.Constraint = "unique"
				idx.Warning = "the prefix index enforces uniqueness on its own fields; the container cannot, so dropping it loses the unique constraint"
			case results[i].ExpireAfterSeconds != nil:
				idx.Constraint = "TTL"
				idx.Warning = "the prefix index is a TTL index; dropping it stops document expiry"
			}

			di = append(di, idx)
		}
	}

	return di, skipped
}
