package fingerprinter

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
)

var (
	MAX_DEPTH_LEVEL     = 10
	DEFAULT_KEY_FILTERS = []string{"^shardVersion$"}
)

type Fingerprint struct {
	Namespace   string
	Operation   string
	Collection  string
	Database    string
	Keys        string
	Fingerprint string
}

type Fingerprinter struct {
	keyFilters []string
}

func NewFingerprinter(keyFilters []string) *Fingerprinter {
	return &Fingerprinter{
		keyFilters: keyFilters,
	}
}

func (f *Fingerprinter) Fingerprint(doc proto.SystemProfile) (Fingerprint, error) {
	realQuery, err := util.GetQueryField(doc)
	if err != nil {
		// Try to encode doc.Query as json for prettiness
		if buf, err := json.Marshal(realQuery); err == nil {
			return Fingerprint{}, fmt.Errorf("%v for query %s", err, string(buf))
		}
		// If we cannot encode as json, return just the error message without the query
		return Fingerprint{}, err
	}
	retKeys := keys(realQuery, f.keyFilters)

	// Proper way to detect if protocol used is "op_msg" or "op_command"
	// would be to look at "doc.Protocol" field,
	// however MongoDB 3.0 doesn't have that field
	// so we need to detect protocol by looking at actual data.
	query := doc.Query
	if doc.Command.Len() > 0 {
		query = doc.Command
	}

	// if there is a sort clause in the query, we have to add all fields in the sort
	// fields list that are not in the query keys list (retKeys)
	if sortKeys, ok := query.Map()["sort"]; ok {
		if sortKeysMap, ok := sortKeys.(bson.M); ok {
			sortKeys := keys(sortKeysMap, f.keyFilters)
			retKeys = append(retKeys, sortKeys...)
		}
	}

	// if there is a orderby clause in the query, we have to add all fields in the sort
	// fields list that are not in the query keys list (retKeys)
	if sortKeys, ok := query.Map()["orderby"]; ok {
		if sortKeysMap, ok := sortKeys.(bson.M); ok {
			sortKeys := keys(sortKeysMap, f.keyFilters)
			retKeys = append(retKeys, sortKeys...)
		}
	}

	// Extract operation, collection, database and namespace
	op := ""
	collection := ""
	database := ""
	ns := strings.SplitN(doc.Ns, ".", 2)
	if len(ns) > 0 {
		database = ns[0]
	}
	if len(ns) == 2 {
		collection = ns[1]
	}
	switch doc.Op {
	case "remove", "update":
		op = doc.Op
	case "insert":
		op = doc.Op
		retKeys = []string{}
	case "query":
		// EXPLAIN MongoDB 2.6:
		// "query" : {
		//   "query" : {
		//
		//   },
		//	 "$explain" : true
		// },
		if _, ok := doc.Query.Map()["$explain"]; ok {
			op = "explain"
			database = ""
			collection = ""
			break
		}
		op = "find"
	case "command":
		if query.Len() == 0 {
			break
		}
		// first key is operation type
		op = query[0].Key
		collection, _ = query[0].Value.(string)
		switch op {
		case "group":
			retKeys = []string{}
			if g, ok := query.Map()["group"]; ok {
				if m, ok := g.(bson.M); ok {
					if f, ok := m["key"]; ok {
						if keysMap, ok := f.(bson.M); ok {
							retKeys = append(retKeys, keys(keysMap, []string{})...)
						}
					}
					if f, ok := m["cond"]; ok {
						if keysMap, ok := f.(bson.M); ok {
							retKeys = append(retKeys, keys(keysMap, []string{})...)
						}
					}
					if f, ok := m["ns"]; ok {
						if ns, ok := f.(string); ok {
							collection = ns
						}
					}
				}
			}
		case "distinct":
			if key, ok := query.Map()["key"]; ok {
				if k, ok := key.(string); ok {
					retKeys = append(retKeys, k)
				}
			}
		case "aggregate":
			retKeys = []string{}
			if v, ok := query.Map()["pipeline"]; ok {
				retKeys = append(retKeys, keys(v, []string{})...)
			}
		case "geoNear":
			retKeys = []string{}
		case "explain":
			database = ""
			collection = ""
			retKeys = []string{}
		case "$eval":
			op = "eval"
			collection = ""
			retKeys = []string{}
		}
	default:
		op = doc.Op
		retKeys = []string{}
	}

	sort.Strings(retKeys)
	retKeys = deduplicate(retKeys)
	keys := strings.Join(retKeys, ",")
	op = strings.ToUpper(op)

	parts := []string{}
	if op != "" {
		parts = append(parts, op)
	}
	if collection != "" {
		parts = append(parts, collection)
	}
	if keys != "" {
		parts = append(parts, keys)
	}

	ns = []string{}
	if database != "" {
		ns = append(ns, database)
	}
	if collection != "" {
		ns = append(ns, collection)
	}
	fp := Fingerprint{
		Operation:   op,
		Namespace:   strings.Join(ns, "."),
		Database:    database,
		Collection:  collection,
		Keys:        keys,
		Fingerprint: strings.Join(parts, " "),
	}

	return fp, nil
}

func keys(query interface{}, keyFilters []string) []string {
	return getKeys(query, keyFilters, 0)
}

func getKeys(query interface{}, keyFilters []string, level int) []string {
	ks := []string{}
	var q []bson.M
	switch v := query.(type) {
	case primitive.M:
		q = append(q, v)
	case []bson.M:
		q = v
	case primitive.A:
		for _, intval := range v {
			ks = append(ks, getKeys(intval, keyFilters, level+1)...)
		}
		return ks
	case proto.BsonD:
		for _, intval := range v {
			ks = append(ks, getKeys(intval, keyFilters, level+1)...)
		}
		return ks
	case primitive.E:
		if matched, _ := regexp.MatchString("^\\$", v.Key); !matched {
			ks = append(ks, v.Key)
		}

		ks = append(ks, getKeys(v.Value, keyFilters, level+1)...)
		return ks
	default:
		return ks
	}

	if level <= MAX_DEPTH_LEVEL {
		for i := range q {
			for key, value := range q[i] {
				if shouldSkipKey(key, keyFilters) {
					continue
				}
				if matched, _ := regexp.MatchString("^\\$", key); !matched {
					ks = append(ks, key)
				}

				ks = append(ks, getKeys(value, keyFilters, level+1)...)
			}
		}
	}
	return ks
}

func shouldSkipKey(key string, keyFilters []string) bool {
	for _, filter := range keyFilters {
		if matched, _ := regexp.MatchString(filter, key); matched {
			return true
		}
	}
	return false
}

func deduplicate(s []string) (r []string) {
	m := map[string]struct{}{}

	for _, v := range s {
		if _, seen := m[v]; !seen {
			r = append(r, v)
			m[v] = struct{}{}
		}
	}

	return r
}
