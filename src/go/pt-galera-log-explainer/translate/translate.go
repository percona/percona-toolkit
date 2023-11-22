package translate

import (
	"encoding/json"
	"sort"
	"sync"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

type translationUnit struct {
	Value     string
	Timestamp time.Time
}

type translationsDB struct {
	// 1 hash: only 1 IP. wsrep_node_address is not dynamic
	// if there's a restart, the hash will change as well anyway
	HashToIP map[string]translationUnit

	// wsrep_node_name is dynamic
	HashToNodeNames map[string][]translationUnit
	IPToNodeNames   map[string][]translationUnit

	// incase methods changed in the middle, tls=>ssl
	IPToMethods map[string][]translationUnit
	rwlock      sync.RWMutex
}

var AssumeIPStable bool = true

var db = translationsDB{}

func init() {
	initTranslationsDB()
}

func initTranslationsDB() {
	db = translationsDB{
		HashToIP:        map[string]translationUnit{},
		HashToNodeNames: map[string][]translationUnit{},
		IPToMethods:     map[string][]translationUnit{},
		IPToNodeNames:   map[string][]translationUnit{},
	}
}

// only useful for tests
func ResetDB() {
	initTranslationsDB()
}

func DBToJson() (string, error) {
	out, err := json.MarshalIndent(db, "", "\t")
	return string(out), err
}

func GetDB() translationsDB {
	return db
}

func AddHashToIP(hash, ip string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	db.HashToIP[hash] = translationUnit{Value: ip, Timestamp: ts}
}

func sameAsLatestValue(m map[string][]translationUnit, key string, newvalue string) bool {
	return len(m[key]) > 0 && m[key][len(m[key])-1].Value == newvalue
}

func AddHashToNodeName(hash, name string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	name = utils.ShortNodeName(name)
	if sameAsLatestValue(db.HashToNodeNames, hash, name) {
		return
	}
	db.HashToNodeNames[hash] = append(db.HashToNodeNames[hash], translationUnit{Value: name, Timestamp: ts})
}

func AddIPToNodeName(ip, name string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	name = utils.ShortNodeName(name)
	if sameAsLatestValue(db.IPToNodeNames, ip, name) {
		return
	}
	db.IPToNodeNames[ip] = append(db.IPToNodeNames[ip], translationUnit{Value: name, Timestamp: ts})
}

func AddIPToMethod(ip, method string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	if sameAsLatestValue(db.IPToMethods, ip, method) {
		return
	}
	db.IPToMethods[ip] = append(db.IPToMethods[ip], translationUnit{Value: method, Timestamp: ts})
}

func GetIPFromHash(hash string) string {
	db.rwlock.RLock()
	defer db.rwlock.RUnlock()
	return db.HashToIP[hash].Value
}

func mostAppropriateValueFromTS(units []translationUnit, ts time.Time) string {

	if len(units) == 0 {
		return ""
	}

	// We start from the first unit, this ensures we can retroactively use information that were
	// seen in the future.
	// the first ever information will be the base, then we will override if there is a more recent version
	cur := units[0]
	for _, unit := range units[1:] {
		if unit.Timestamp.After(cur.Timestamp) && (unit.Timestamp.Before(ts) || unit.Timestamp.Equal(ts)) {
			cur = unit
		}
	}
	return cur.Value
}

func GetNodeNameFromHash(hash string, ts time.Time) string {
	db.rwlock.RLock()
	names := db.HashToNodeNames[hash]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(names, ts)
}

func GetNodeNameFromIP(ip string, ts time.Time) string {
	db.rwlock.RLock()
	names := db.IPToNodeNames[ip]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(names, ts)
}

func GetMethodFromIP(ip string, ts time.Time) string {
	db.rwlock.RLock()
	methods := db.IPToMethods[ip]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(methods, ts)
}

func (db *translationsDB) getHashSliceFromIP(ip string) []translationUnit {
	db.rwlock.RLock()
	defer db.rwlock.RUnlock()

	units := []translationUnit{}
	for hash, unit := range db.HashToIP {
		if unit.Value == ip {
			units = append(units, translationUnit{Value: hash, Timestamp: unit.Timestamp})
		}
	}

	sort.Slice(units, func(i, j int) bool {
		return units[i].Timestamp.Before(units[j].Timestamp)
	})
	return units
}

func (db *translationsDB) getHashFromIP(ip string, ts time.Time) string {
	units := db.getHashSliceFromIP(ip)
	return mostAppropriateValueFromTS(units, ts)
}

// SimplestInfoFromIP is useful to get the most easily to read string for a given IP
// This only has impacts on display
// In order of preference: wsrep_node_name (or galera "node" name), hostname, ip
func SimplestInfoFromIP(ip string, date time.Time) string {
	if nodename := GetNodeNameFromIP(ip, date); nodename != "" {
		return nodename
	}

	// This means we trust the fact that some nodes hashes/names sharing the same IP
	// will ultimately be from the same node. On on-premise setups this is safe to assume
	if AssumeIPStable {
		for _, units := range db.getHashSliceFromIP(ip) {
			if nodename := GetNodeNameFromHash(units.Value, date); nodename != "" {
				return nodename
			}
		}
		// on k8s setups, we cannot assume this, IPs are reused between nodes.
		// we have to strictly use ip=>hash pairs we saw in logs at specific timeframe
	} else {
		if hash := db.getHashFromIP(ip, date); hash != "" {
			if nodename := GetNodeNameFromHash(hash, date); nodename != "" {
				return nodename
			}
		}
	}
	return ip
}

func SimplestInfoFromHash(hash string, date time.Time) string {
	if nodename := GetNodeNameFromHash(hash, date); nodename != "" {
		return nodename
	}

	if ip := GetIPFromHash(hash); ip != "" {
		return SimplestInfoFromIP(ip, date)
	}
	return hash
}
