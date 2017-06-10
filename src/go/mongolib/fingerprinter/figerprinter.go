package fingerprinter

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/percona/percona-toolkit/src/go/mongolib/util"
)

var (
	MAX_DEPTH_LEVEL     = 10
	DEFAULT_KEY_FILTERS = []string{"^shardVersion$", "^\\$"}
)

type Fingerprinter interface {
	Fingerprint(query map[string]interface{}) (string, error)
}

type Fingerprint struct {
	keyFilters []string
}

func NewFingerprinter(keyFilters []string) *Fingerprint {
	return &Fingerprint{
		keyFilters: keyFilters,
	}
}

// Query is the top level map query element
// Example for MongoDB 3.2+
//     "query" : {
//        "find" : "col1",
//        "filter" : {
//            "s2" : {
//                "$lt" : "54701",
//                "$gte" : "73754"
//            }
//        },
//        "sort" : {
//            "user_id" : 1
//        }
//     }
func (f *Fingerprint) Fingerprint(query map[string]interface{}) (string, error) {

	realQuery, err := util.GetQueryField(query)
	if err != nil {
		// Try to encode doc.Query as json for prettiness
		if buf, err := json.Marshal(realQuery); err == nil {
			return "", fmt.Errorf("%v for query %s", err, string(buf))
		}
		// If we cannot encode as json, return just the error message without the query
		return "", err
	}
	retKeys := keys(realQuery, f.keyFilters)

	sort.Strings(retKeys)

	// if there is a sort clause in the query, we have to add all fields in the sort
	// fields list that are not in the query keys list (retKeys)
	if sortKeys, ok := query["sort"]; ok {
		if sortKeysMap, ok := sortKeys.(map[string]interface{}); ok {
			sortKeys := keys(sortKeysMap, f.keyFilters)
			for _, sortKey := range sortKeys {
				if !inSlice(sortKey, retKeys) {
					retKeys = append(retKeys, sortKey)
				}
			}
		}
	}

	return strings.Join(retKeys, ","), nil
}

func inSlice(str string, list []string) bool {
	for _, v := range list {
		if v == str {
			return true
		}
	}
	return false
}

func keys(query map[string]interface{}, keyFilters []string) []string {
	return getKeys(query, keyFilters, 0)
}

func getKeys(query map[string]interface{}, keyFilters []string, level int) []string {
	ks := []string{}
	for key, value := range query {
		if shouldSkipKey(key, keyFilters) {
			continue
		}
		ks = append(ks, key)
		if m, ok := value.(map[string]interface{}); ok {
			level++
			if level <= MAX_DEPTH_LEVEL {
				ks = append(ks, getKeys(m, keyFilters, level)...)
			}
		}
	}
	sort.Strings(ks)
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
