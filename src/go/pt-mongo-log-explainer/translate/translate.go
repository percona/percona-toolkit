// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
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

package translate

import (
	"encoding/json"
	"sort"
	"sync"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
)

type translationUnit struct {
	Value     string
	Timestamp time.Time
}

type translationsDB struct {
	// 1 hash: only 1 IP. If there's a restart, the hash will change as well.
	HashToIP map[string]*translationUnit

	HashToNodeNames map[string][]translationUnit
	IPToNodeNames   map[string][]translationUnit

	// in case methods changed in the middle, tcp=>ssl
	IPToMethods map[string][]translationUnit

	// MongoDB identity: host:port -> nodename, and nodename -> host:port
	HostPortToNodeNames map[string][]translationUnit
	NodeNameToHostPorts map[string][]translationUnit
	NodeNameToRSNames   map[string][]translationUnit

	rwlock sync.RWMutex
}

var AssumeIPStable bool = true

var db = translationsDB{}

func init() {
	initTranslationsDB()
}

func initTranslationsDB() {
	db = translationsDB{
		HashToIP:            map[string]*translationUnit{},
		HashToNodeNames:     map[string][]translationUnit{},
		IPToMethods:         map[string][]translationUnit{},
		IPToNodeNames:       map[string][]translationUnit{},
		HostPortToNodeNames: map[string][]translationUnit{},
		NodeNameToHostPorts: map[string][]translationUnit{},
		NodeNameToRSNames:   map[string][]translationUnit{},
	}
}

// only useful for tests
func ResetDB() {
	initTranslationsDB()
}

func DBToJson() (string, error) {
	db.rwlock.RLock()
	defer db.rwlock.RUnlock()
	snap := struct {
		HashToIP            map[string]*translationUnit
		HashToNodeNames     map[string][]translationUnit
		IPToNodeNames       map[string][]translationUnit
		IPToMethods         map[string][]translationUnit
		HostPortToNodeNames map[string][]translationUnit
		NodeNameToHostPorts map[string][]translationUnit
		NodeNameToRSNames   map[string][]translationUnit
	}{
		HashToIP:            db.HashToIP,
		HashToNodeNames:     db.HashToNodeNames,
		IPToNodeNames:       db.IPToNodeNames,
		IPToMethods:         db.IPToMethods,
		HostPortToNodeNames: db.HostPortToNodeNames,
		NodeNameToHostPorts: db.NodeNameToHostPorts,
		NodeNameToRSNames:   db.NodeNameToRSNames,
	}
	out, err := json.MarshalIndent(snap, "", "\t")
	return string(out), err
}

func GetDB() *translationsDB {
	return &db
}

func (tu *translationUnit) UpdateTimestamp(ts time.Time) {
	// we want to avoid gap of information, so the earliest proof should be kept
	if tu.Timestamp.After(ts) {
		tu.Timestamp = ts
	}
}

func AddHashToIP(hash, ip string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	latestValue, ok := db.HashToIP[hash]
	if ok && latestValue != nil {
		latestValue.UpdateTimestamp(ts)
	} else {
		db.HashToIP[hash] = &translationUnit{Value: ip, Timestamp: ts}
	}
}

func getLatestValue(m map[string][]translationUnit, key string) *translationUnit {
	if len(m[key]) == 0 {
		return nil
	}
	return &m[key][len(m[key])-1]
}

func upsertToMap(m map[string][]translationUnit, key string, tu translationUnit) {

	latestValue := getLatestValue(m, key)
	if latestValue == nil || latestValue.Value != tu.Value {
		m[key] = append(m[key], tu)
		return
	}
	// we want to avoid gap of information, so the earliest proof should be kept
	if latestValue.Timestamp.After(tu.Timestamp) {
		latestValue.Timestamp = tu.Timestamp
	}
}

func AddHashToNodeName(hash, name string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	name = utils.ShortNodeName(name)
	upsertToMap(db.HashToNodeNames, hash, translationUnit{Value: name, Timestamp: ts})
}

func AddIPToNodeName(ip, name string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	name = utils.ShortNodeName(name)
	upsertToMap(db.IPToNodeNames, ip, translationUnit{Value: name, Timestamp: ts})
}

func AddIPToMethod(ip, method string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	upsertToMap(db.IPToMethods, ip, translationUnit{Value: method, Timestamp: ts})
}

func GetIPFromHash(hash string) string {
	db.rwlock.RLock()
	defer db.rwlock.RUnlock()
	ip, ok := db.HashToIP[hash]
	if ok {
		return ip.Value
	}
	return ""
}

func mostAppropriateValueFromTS(units []translationUnit, ts time.Time) translationUnit {

	if len(units) == 0 {
		return translationUnit{}
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
	return cur
}

func GetNodeNameFromHash(hash string, ts time.Time) string {
	db.rwlock.RLock()
	names := db.HashToNodeNames[hash]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(names, ts).Value
}

func GetNodeNameFromIP(ip string, ts time.Time) string {
	db.rwlock.RLock()
	names := db.IPToNodeNames[ip]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(names, ts).Value
}

func GetMethodFromIP(ip string, ts time.Time) string {
	db.rwlock.RLock()
	methods := db.IPToMethods[ip]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(methods, ts).Value
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
	return mostAppropriateValueFromTS(units, ts).Value
}

// SimplestInfoFromIP returns the most human-readable label for a given IP.
// In order of preference: node name, hostname, ip
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

// AddPeerIP records that an IP was seen connecting to a cluster node.
// Unlike AddOwnIP (called on LogCtx), this does not associate the IP with the
// parsing node — it just ensures the IP exists in the DB so whois can find it.
func AddPeerIP(ip string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	if _, ok := db.IPToNodeNames[ip]; !ok {
		db.IPToNodeNames[ip] = nil
	}
}

func AddHostPortToNodeName(hostport, name string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	name = utils.ShortNodeName(name)
	upsertToMap(db.HostPortToNodeNames, hostport, translationUnit{Value: name, Timestamp: ts})
	upsertToMap(db.NodeNameToHostPorts, name, translationUnit{Value: hostport, Timestamp: ts})
}

func AddNodeNameToRSName(nodename, rsname string, ts time.Time) {
	db.rwlock.Lock()
	defer db.rwlock.Unlock()
	nodename = utils.ShortNodeName(nodename)
	upsertToMap(db.NodeNameToRSNames, nodename, translationUnit{Value: rsname, Timestamp: ts})
}

func GetNodeNameFromHostPort(hostport string, ts time.Time) string {
	db.rwlock.RLock()
	names := db.HostPortToNodeNames[hostport]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(names, ts).Value
}

func GetHostPortsFromNodeName(name string, ts time.Time) []string {
	db.rwlock.RLock()
	units := db.NodeNameToHostPorts[name]
	db.rwlock.RUnlock()
	var out []string
	for _, u := range units {
		out = append(out, u.Value)
	}
	return out
}

func GetRSNameFromNodeName(name string, ts time.Time) string {
	db.rwlock.RLock()
	units := db.NodeNameToRSNames[name]
	db.rwlock.RUnlock()
	return mostAppropriateValueFromTS(units, ts).Value
}

func IsHostPortKnown(hp string) bool {
	db.rwlock.RLock()
	defer db.rwlock.RUnlock()
	_, ok := db.HostPortToNodeNames[hp]
	return ok
}

func IsNodeUUIDKnown(uuid string) bool {
	db.rwlock.RLock()
	defer db.rwlock.RUnlock()

	_, ok := db.HashToIP[uuid]
	if ok {
		return true
	}
	_, ok = db.HashToNodeNames[uuid]
	return ok
}

func IsNodeNameKnown(name string) bool {
	db.rwlock.RLock()
	defer db.rwlock.RUnlock()

	if _, ok := db.NodeNameToHostPorts[name]; ok {
		return true
	}
	if _, ok := db.NodeNameToRSNames[name]; ok {
		return true
	}
	for _, nodenames := range db.HashToNodeNames {
		for _, nodename := range nodenames {
			if name == nodename.Value {
				return true
			}
		}
	}
	for _, nodenames := range db.IPToNodeNames {
		for _, nodename := range nodenames {
			if name == nodename.Value {
				return true
			}
		}
	}
	for _, nodenames := range db.HostPortToNodeNames {
		for _, nodename := range nodenames {
			if name == nodename.Value {
				return true
			}
		}
	}
	return false
}
