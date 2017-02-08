package util

import (
	"fmt"
	"strings"

	"github.com/bradfitz/slice"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"
	"github.com/pkg/errors"
	mgo "gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
)

func GetReplicasetMembersNew(dialer pmgo.Dialer, di *mgo.DialInfo) ([]proto.Members, error) {
	hostnames, err := GetHostnames(dialer, di)
	if err != nil {
		return nil, err
	}
	replicaMembers := []proto.Members{}
	for _, hostname := range hostnames {
		if serverStatus, err := GetServerStatus(dialer, di, hostname); err == nil {

			m := proto.Members{
				ID:            serverStatus.Pid,
				Name:          hostname,
				StorageEngine: serverStatus.StorageEngine,
				Set:           serverStatus.Repl.SetName,
			}
			if serverStatus.Repl.IsMaster != nil && serverStatus.Repl.IsMaster.(bool) {
				m.StateStr = "PRIMARY"
			}
			if serverStatus.Repl.Secondary != nil && serverStatus.Repl.Secondary.(bool) {
				m.StateStr = "SECONDARY"
			}
			replicaMembers = append(replicaMembers, m)
		}

	}

	return replicaMembers, nil
}

func GetReplicasetMembers(dialer pmgo.Dialer, di *mgo.DialInfo) ([]proto.Members, error) {
	hostnames, err := GetHostnames(dialer, di)
	if err != nil {
		return nil, err
	}
	membersMap := make(map[string]proto.Members)
	members := []proto.Members{}

	for _, hostname := range hostnames {
		tmpdi := *di
		tmpdi.Addrs = []string{hostname}
		session, err := dialer.DialWithInfo(&tmpdi)
		if err != nil {
			return nil, errors.Wrapf(err, "getReplicasetMembers. cannot connect to %s", hostname)
		}

		cmdOpts := proto.CommandLineOptions{}
		session.DB("admin").Run(bson.D{{"getCmdLineOpts", 1}, {"recordStats", 1}}, &cmdOpts)

		rss := proto.ReplicaSetStatus{}
		if err = session.Run(bson.M{"replSetGetStatus": 1}, &rss); err != nil {
			m := proto.Members{
				Name: hostname,
			}
			m.StateStr = cmdOpts.Parsed.Sharding.ClusterRole

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
				m.StateStr = cmdOpts.Parsed.Sharding.ClusterRole + "/" + m.StateStr
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

func GetHostnames(dialer pmgo.Dialer, di *mgo.DialInfo) ([]string, error) {
	hostnames := []string{di.Addrs[0]}
	session, err := dialer.DialWithInfo(di)
	if err != nil {
		return hostnames, err
	}
	defer session.Close()

	var shardsMap proto.ShardsMap
	err = session.Run("getShardMap", &shardsMap)
	if err != nil {
		return hostnames, errors.Wrap(err, "cannot list shards")
	}

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

	hm := make(map[string]bool)
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
		hostnames = []string{} // re-init because it has di.Addr[0]
		for host := range hm {
			hostnames = append(hostnames, host)
		}
	}
	return hostnames, nil
}

// This function is like GetHostnames but it uses listShards instead of getShardMap
// so it won't include config servers in the returned list
func GetShardsHosts(dialer pmgo.Dialer, di *mgo.DialInfo) ([]string, error) {
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

func GetServerStatus(dialer pmgo.Dialer, di *mgo.DialInfo, hostname string) (proto.ServerStatus, error) {
	ss := proto.ServerStatus{}

	tmpdi := *di
	tmpdi.Addrs = []string{hostname}
	// tmpdi.Direct = true
	// tmpdi.Timeout = 5 * time.Second
	// tmpdi.FailFast = false

	session, err := dialer.DialWithInfo(&tmpdi)
	if err != nil {
		fmt.Printf("error %s\n", err.Error())
		return ss, errors.Wrapf(err, "getReplicasetMembers. cannot connect to %s", hostname)
	}
	defer session.Close()

	if err := session.DB("admin").Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, &ss); err != nil {
		fmt.Printf("error 2%s\n", err.Error())
		return ss, errors.Wrap(err, "GetHostInfo.serverStatus")
	}

	return ss, nil
}
