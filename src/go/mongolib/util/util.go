package util

import (
	"strings"
	"time"

	"github.com/bradfitz/slice"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"
	"github.com/pkg/errors"
	mgo "gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
)

func GetReplicasetMembers(dialer pmgo.Dialer, di *pmgo.DialInfo) ([]proto.Members, error) {
	hostnames, err := GetHostnames(dialer, di)
	if err != nil {
		return nil, err
	}
	membersMap := make(map[string]proto.Members)
	members := []proto.Members{}

	for _, hostname := range hostnames {
		session, err := dialer.DialWithInfo(getTmpDI(di, hostname))
		if err != nil {
			continue
		}
		defer session.Close()
		session.SetMode(mgo.Monotonic, true)

		cmdOpts := proto.CommandLineOptions{}
		session.DB("admin").Run(bson.D{{"getCmdLineOpts", 1}, {"recordStats", 1}}, &cmdOpts)

		rss := proto.ReplicaSetStatus{}
		if err = session.Run(bson.M{"replSetGetStatus": 1}, &rss); err != nil {
			m := proto.Members{
				Name: hostname,
			}
			m.StateStr = strings.ToUpper(cmdOpts.Parsed.Sharding.ClusterRole)

			if serverStatus, err := GetServerStatus(dialer, di, m.Name); err == nil {
				m.ID = serverStatus.Pid
				m.StorageEngine = serverStatus.StorageEngine
			}
			membersMap[m.Name] = m
			continue // If a host is a mongos we cannot get info but is not a real error
		}

		for _, m := range rss.Members {
			if _, ok := membersMap[m.Name]; ok {
				continue // already exists
			}
			m.Set = rss.Set
			if serverStatus, err := GetServerStatus(dialer, di, m.Name); err == nil {
				m.ID = serverStatus.Pid
				m.StorageEngine = serverStatus.StorageEngine
				if cmdOpts.Parsed.Sharding.ClusterRole == "" {
					m.StateStr = m.StateStr
				} else {
					m.StateStr = cmdOpts.Parsed.Sharding.ClusterRole + "/" + m.StateStr
				}
				m.StateStr = strings.ToUpper(m.StateStr)
			}
			membersMap[m.Name] = m
		}

		session.Close()
	}

	for _, member := range membersMap {
		members = append(members, member)
	}

	slice.Sort(members, func(i, j int) bool { return members[i].Name < members[j].Name })
	return members, nil
}

func GetHostnames(dialer pmgo.Dialer, di *pmgo.DialInfo) ([]string, error) {
	hostnames := []string{di.Addrs[0]}
	di.Direct = true
	di.Timeout = 2 * time.Second

	session, err := dialer.DialWithInfo(di)
	if err != nil {
		return hostnames, err
	}
	session.SetMode(mgo.Monotonic, true)

	// Probably we are connected to an individual member of a replica set
	rss := proto.ReplicaSetStatus{}
	if err := session.Run(bson.M{"replSetGetStatus": 1}, &rss); err == nil {
		return buildHostsListFromReplStatus(rss), nil
	}

	defer session.Close()

	// Try getShardMap first. If we are connected to a mongos it will return
	// all hosts, including config hosts
	var shardsMap proto.ShardsMap
	err = session.Run("getShardMap", &shardsMap)
	if err == nil && len(shardsMap.Map) > 0 {
		// if the only element getShardMap returns is the list of config servers,
		// it means we are connected to a replicaSet member and getShardMap is not
		// the answer we want.
		_, ok := shardsMap.Map["config"]
		if ok && len(shardsMap.Map) > 1 {
			return buildHostsListFromShardMap(shardsMap), nil
		}
	}

	return hostnames, nil
}

func buildHostsListFromReplStatus(replStatus proto.ReplicaSetStatus) []string {
	/*
	   "members" : [
	            {
	                    "_id" : 0,
	                    "name" : "localhost:17001",
	                    "health" : 1,
	                    "state" : 1,
	                    "stateStr" : "PRIMARY",
	                    "uptime" : 4700,
	                    "optime" : Timestamp(1486554836, 1),
	                    "optimeDate" : ISODate("2017-02-08T11:53:56Z"),
	                    "electionTime" : Timestamp(1486651810, 1),
	                    "electionDate" : ISODate("2017-02-09T14:50:10Z"),
	                    "configVersion" : 1,
	                    "self" : true
	            },
	*/

	hostnames := []string{}
	for _, member := range replStatus.Members {
		hostnames = append(hostnames, member.Name)
	}
	return hostnames
}

func buildHostsListFromShardMap(shardsMap proto.ShardsMap) []string {
	/* Example
	mongos> db.getSiblingDB('admin').runCommand('getShardMap')
	{
	        "map" : {
	                "config" : "localhost:19001,localhost:19002,localhost:19003",
	                "localhost:17001" : "r1/localhost:17001,localhost:17002,localhost:17003",
	                "r1" : "r1/localhost:17001,localhost:17002,localhost:17003",
	                "r1/localhost:17001,localhost:17002,localhost:17003" : "r1/localhost:17001,localhost:17002,localhost:17003",
	        },
	        "ok" : 1
	}
	*/

	hostnames := []string{}
	hm := make(map[string]bool)

	// Since shardMap can return repeated hosts in different rows, we need a Set
	// but there is no Set in Go so, we are going to create a map and the loop
	// through the keys to get a list of unique host names
	if shardsMap.Map != nil {
		for _, val := range shardsMap.Map {
			m := strings.Split(val, "/")
			hostsStr := ""
			switch len(m) {
			case 1:
				hostsStr = m[0] // there is no / in the hosts list
			case 2:
				hostsStr = m[1] // there is a / in the string. Remove the prefix until the / and keep the rest
			}
			// since there is no Sets in Go, build a map where the value is the map key
			hosts := strings.Split(hostsStr, ",")
			for _, host := range hosts {
				hm[host] = false
			}
		}
		for host := range hm {
			hostnames = append(hostnames, host)
		}
	}
	return hostnames
}

// This function is like GetHostnames but it uses listShards instead of getShardMap
// so it won't include config servers in the returned list
func GetShardedHosts(dialer pmgo.Dialer, di *pmgo.DialInfo) ([]string, error) {
	hostnames := []string{di.Addrs[0]}
	session, err := dialer.DialWithInfo(di)
	if err != nil {
		return hostnames, err
	}
	defer session.Close()

	shardsInfo := &proto.ShardsInfo{}
	err = session.Run("listShards", shardsInfo)
	if err != nil {
		return hostnames, errors.Wrap(err, "cannot list shards")
	}

	if shardsInfo != nil {
		for _, shardInfo := range shardsInfo.Shards {
			m := strings.Split(shardInfo.Host, "/")
			h := strings.Split(m[1], ",")
			hostnames = append(hostnames, h[0])
		}
	}
	return hostnames, nil
}

func getTmpDI(di *pmgo.DialInfo, hostname string) *pmgo.DialInfo {
	tmpdi := *di
	tmpdi.Addrs = []string{hostname}
	tmpdi.Direct = true
	tmpdi.Timeout = 2 * time.Second

	return &tmpdi
}

func GetServerStatus(dialer pmgo.Dialer, di *pmgo.DialInfo, hostname string) (proto.ServerStatus, error) {
	ss := proto.ServerStatus{}

	tmpdi := getTmpDI(di, hostname)
	session, err := dialer.DialWithInfo(tmpdi)
	if err != nil {
		return ss, errors.Wrapf(err, "getReplicasetMembers. cannot connect to %s", hostname)
	}
	defer session.Close()
	session.SetMode(mgo.Monotonic, true)

	if err := session.DB("admin").Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, &ss); err != nil {
		return ss, errors.Wrap(err, "GetHostInfo.serverStatus")
	}

	return ss, nil
}
