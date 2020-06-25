package fingerprinter

import (
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

const (
	maxDepthLevel = 10
)

// Fingerprint models the MongnDB query fingeprint result fields.
type Fingerprint struct {
	Namespace   string
	Operation   string
	Collection  string
	Database    string
	Keys        string
	Fingerprint string
}

// Fingerprinter holds unexported fields and public methods for fingerprinting queries.
type Fingerprinter struct {
	keyFilters []string
}

// DefaultKeyFilters returns the default keys used to filter out some keys
// from the fingerprinter.
func DefaultKeyFilters() []string {
	return []string{"^shardVersion$"}
}

// NewFingerprinter returns a new Fingerprinter object
func NewFingerprinter(keyFilters []string) *Fingerprinter {
	return &Fingerprinter{
		keyFilters: keyFilters,
	}
}

// Fingerprint process a query input to build it's fingerprint.
func (f *Fingerprinter) Fingerprint(doc proto.SystemProfile) (Fingerprint, error) {
	realQuery, err := GetQueryFieldD(doc)
	if err != nil {
		return Fingerprint{}, err
	}
	retKeys := keys(realQuery, f.keyFilters)

	// Proper way to detect if protocol used is "op_msg" or "op_command"
	// would be to look at "doc.Protocol" field,
	// however MongoDB 3.0 doesn't have that field
	// so we need to detect protocol by looking at actual data.
	query := doc.Query
	if len(doc.Command) > 0 {
		query = doc.Command
	}

	// if there is a sort clause in the query, we have to add all fields in the sort
	// fields list that are not in the query keys list (retKeys)
	if sortKeys, ok := query.Map()["sort"]; ok {
		sortKeys := keys(sortKeys, f.keyFilters)
		retKeys = append(retKeys, sortKeys...)
	}

	// if there is a orderby clause in the query, we have to add all fields in the sort
	// fields list that are not in the query keys list (retKeys)
	if sortKeys, ok := query.Map()["orderby"]; ok {
		sortKeys := keys(sortKeys, f.keyFilters)
		retKeys = append(retKeys, sortKeys...)
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
		if len(query) == 0 {
			break
		}
		// first key is operation type
		op = query[0].Key
		collection, _ = query[0].Value.(string)
		switch op {
		case "group":
			retKeys = []string{}
			if g, ok := query.Map()["group"]; ok {
				m, err := asMap(g)
				if err != nil {
					return Fingerprint{}, err
				}

				if f, ok := m["key"]; ok {
					retKeys = append(retKeys, keys(f, []string{})...)
				}
				if f, ok := m["cond"]; ok {
					retKeys = append(retKeys, keys(f, []string{})...)
				}
				if f, ok := m["ns"]; ok {
					if ns, ok := f.(string); ok {
						collection = ns
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
	case primitive.D:
		for _, intval := range v {
			ks = append(ks, getKeys(intval, keyFilters, level+1)...)
		}
		return ks
	case []bson.M:
		q = v
	case primitive.A:
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

	if level <= maxDepthLevel {
		for i := range q {
			for key, value := range q[i] {
				if shouldSkipKey(key, keyFilters) {
					continue
				}
				if !strings.HasPrefix(key, "$") {
					ks = append(ks, key)
				}

				ks = append(ks, getKeys(value, keyFilters, level+1)...)
			}
		}
	}
	return ks
}

// Check if a particular key should be excluded from the analysis based on the filters.
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

// GetQueryFieldD returns the correct field to build the fingerprint, based on the operation.
func GetQueryFieldD(doc proto.SystemProfile) (primitive.M, error) {
	// Proper way to detect if protocol used is "op_msg" or "op_command"
	// would be to look at "doc.Protocol" field,
	// however MongoDB 3.0 doesn't have that field
	// so we need to detect protocol by looking at actual data.
	query := doc.Query
	if len(doc.Command) > 0 {
		query = doc.Command
		if doc.Op == "update" || doc.Op == "remove" {
			if squery, ok := query.Map()["q"]; ok {
				switch v := squery.(type) {
				case primitive.M:
					return v, nil
				case primitive.D:
					return v.Map(), nil
				default:
					return nil, fmt.Errorf("don't know how to handle %T in 'doc.Command' field", v)
				}
			}
		}
	}

	// "query" in MongoDB 3.0 can look like this:
	// {
	//  	"op" : "query",
	//  	"ns" : "test.coll",
	//  	"query" : {
	//  		"a" : 1
	//  	},
	// 		...
	// }
	//
	// but also it can have "query" subkey like this:
	// {
	//  	"op" : "query",
	//  	"ns" : "test.coll",
	//  	"query" : {
	//  		"query" : {
	//  			"$and" : [
	//  			]
	//  		},
	//  		"orderby" : {
	//  			"k" : -1
	//  		}
	//  	},
	// 		...
	// }
	//
	if squery, ok := query.Map()["query"]; ok {
		return asMap(squery)
	}

	// "query" in MongoDB 3.2+ is better structured and always has a "filter" subkey:
	if squery, ok := query.Map()["filter"]; ok {
		return asMap(squery)
	}

	// {"ns":"test.system.js","op":"query","query":{"find":"system.js"}}
	if len(query) == 1 && query[0].Key == "find" {
		return primitive.M{}, nil
	}

	return query.Map(), nil
}

func asMap(field interface{}) (primitive.M, error) {
	switch v := field.(type) {
	case primitive.M:
		return v, nil
	case primitive.D:
		return v.Map(), nil
	default:
		return nil, fmt.Errorf("don't know how to handle %T", v)
	}
}
