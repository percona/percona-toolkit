// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
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

package main

import (
	"fmt"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/oplog"
)

func fp(v float64) *float64 {
	return &v
}

var wiredTiger = proto.StorageEngine{Name: "wiredTiger", SupportsCommittedReads: true, Persistent: true}

func walkedSet() []oplog.Member {
	return []oplog.Member{
		{
			Host: "h3:27017", Set: "rs", State: "SECONDARY", Pid: 303, Engine: wiredTiger,
			Priority: fp(0), Votes: fp(0), Hidden: true, DelaySecs: 3600,
		},
		{Host: "h1:27017", Set: "rs", State: "PRIMARY", Self: true, Pid: 101, Engine: wiredTiger, Priority: fp(2), Votes: fp(1)},
		{Host: "h2:27017", Set: "rs", State: "SECONDARY", Priority: fp(0.5), Votes: fp(1)},
		{Host: "arb:27017", Set: "rs", State: "ARBITER", Arbiter: true, Priority: fp(0), Votes: fp(1)},
	}
}

func TestRoleText(t *testing.T) {
	tests := []struct {
		state   string
		hidden  bool
		delay   int64
		setRole string
		want    string
	}{
		{"PRIMARY", false, 0, "", "PRIMARY"},
		{"SECONDARY", true, 0, "", "SECONDARY (hidden)"},
		{"SECONDARY", true, 3600, "", "SECONDARY (hidden, delayed 3600 s)"},
		{"SECONDARY", false, 60, "", "SECONDARY (delayed 60 s)"},
		{"PRIMARY", false, 0, "SHARDSVR", "SHARDSVR/PRIMARY"},
		{"SECONDARY", true, 0, "CONFIGSVR", "CONFIGSVR/SECONDARY (hidden)"},
		{"ARBITER", false, 0, "", "ARBITER"},
		{"", true, 0, "SHARDSVR", ""},
	}

	for _, tt := range tests {
		assert.Equal(t, tt.want, roleText(tt.state, tt.hidden, tt.delay, tt.setRole))
	}
}

func TestBuildInstances(t *testing.T) {
	members, details, read, total := buildInstances(walkedSet())

	names := make([]string, 0, len(members))
	for _, m := range members {
		names = append(names, m.Name)
	}
	assert.Equal(t, []string{"arb:27017", "h1:27017", "h2:27017", "h3:27017"}, names)

	assert.Equal(t, int64(0), members[0].ID)
	assert.Equal(t, int64(101), members[1].ID)
	assert.Equal(t, int64(0), members[2].ID, "an unread member never gets another host's PID")
	assert.Equal(t, int64(303), members[3].ID)
	assert.Equal(t, "ARBITER", members[0].StateStr)
	assert.Equal(t, "SECONDARY", members[3].StateStr)
	assert.Equal(t, wiredTiger, members[3].StorageEngine)
	assert.Empty(t, members[2].StorageEngine.Name)
	assert.Equal(t, "rs", members[2].Set)

	assert.Equal(t, []memberDetail{
		{Host: "arb:27017", Priority: fp(0), Votes: fp(1)},
		{Host: "h1:27017", Priority: fp(2), Votes: fp(1)},
		{Host: "h2:27017", Priority: fp(0.5), Votes: fp(1)},
		{Host: "h3:27017", Priority: fp(0), Votes: fp(0), Hidden: true, DelaySecs: 3600},
	}, details)
	assert.Equal(t, 2, read)
	assert.Equal(t, 3, total)

	shard, _, _, _ := buildInstances([]oplog.Member{{Host: "s1:1", Set: "sh1", State: "PRIMARY", SetRole: "SHARDSVR"}})
	assert.Equal(t, "SHARDSVR/PRIMARY", shard[0].StateStr)

	none, noDetails, _, _ := buildInstances(nil)
	assert.Nil(t, none)
	assert.Nil(t, noDetails)
}

func instancesLines(t *testing.T, ci *collectedInfo) []string {
	t.Helper()

	out, err := formatResults(ci, "text")
	require.NoError(t, err)

	text := string(out)
	start := strings.Index(text, "# Instances")
	require.GreaterOrEqual(t, start, 0, text)

	var lines []string
	for _, l := range strings.Split(text[start:], "\n")[1:] {
		if l == "" || strings.HasPrefix(l, "#") {
			break
		}
		lines = append(lines, l)
	}

	return lines
}

func TestFormatInstances(t *testing.T) {
	members, details, _, _ := buildInstances(walkedSet())
	lines := instancesLines(t, &collectedInfo{ReplicaMembers: members, MemberDetails: details})

	require.Len(t, lines, 5)
	assert.Regexp(t, regexp.MustCompile(`^\s+PID  Host\s+Type\s+ReplSet  Engine\s+Priority  Votes$`), lines[0])

	hostCol := strings.Index(lines[0], "Host")
	typeCol := strings.Index(lines[0], "Type")
	hosts := []string{"arb:27017", "h1:27017", "h2:27017", "h3:27017"}
	types := []string{"ARBITER", "PRIMARY", "SECONDARY", "SECONDARY"}
	for i, l := range lines[1:] {
		assert.Equal(t, hostCol, strings.Index(l, hosts[i]), l)
		assert.True(t, strings.HasPrefix(l[typeCol:], types[i]), l)
		assert.Equal(t, l, strings.TrimRight(l, " "))
	}

	assert.Equal(t, "arb:27017", strings.TrimSpace(lines[1][:typeCol]))
	assert.Equal(t, "ARBITER", strings.Fields(lines[1][typeCol:])[0])
	assert.Equal(t, "101", strings.TrimSpace(lines[2][:hostCol]))
	assert.Empty(t, strings.TrimSpace(lines[3][:hostCol]))
	assert.Contains(t, lines[3], "0.5")
	assert.Equal(t, "303", strings.TrimSpace(lines[4][:hostCol]))
	assert.Contains(t, lines[4], "SECONDARY (hidden, delayed 3600 s)")
	assert.Regexp(t, regexp.MustCompile(`wiredTiger\s+0\s+0$`), lines[4])
	assert.Regexp(t, regexp.MustCompile(`PRIMARY\s+rs\s+wiredTiger\s+2\s+1$`), lines[2])

	standalone := instancesLines(t, &collectedInfo{HostInfo: &hostInfo{NodeType: "mongod"}})
	require.Len(t, standalone, 2)
	assert.Equal(t, "no replica sets found", strings.TrimSpace(standalone[1]))
}

func TestFormatInstancesWithoutDetails(t *testing.T) {
	lines := instancesLines(t, &collectedInfo{ReplicaMembers: []proto.Members{{Name: "a:1", StateStr: "PRIMARY", Set: "rs"}}})

	require.Len(t, lines, 2)
	assert.Regexp(t, regexp.MustCompile(`^\s+a:1\s+PRIMARY\s+rs$`), lines[1])

	noSet := instancesLines(t, &collectedInfo{ReplicaMembers: []proto.Members{{Name: "a:1"}}})
	require.Len(t, noSet, 2)
	assert.Regexp(t, regexp.MustCompile(`^\s+a:1\s+-$`), noSet[1])
}

func TestSetHostRole(t *testing.T) {
	hi := &hostInfo{NodeType: "replset"}
	setHostRole(hi, walkedSet())
	assert.Equal(t, "PRIMARY", hi.ReplRole)
	assert.Equal(t, fp(2), hi.Priority)
	assert.Equal(t, fp(1), hi.Votes)
	assert.False(t, hi.Hidden)

	hidden := walkedSet()
	hidden[1].Self = false
	hidden[0].Self = true
	hi = &hostInfo{NodeType: "replset"}
	setHostRole(hi, hidden)
	assert.Equal(t, "SECONDARY (hidden, delayed 3600 s)", hi.ReplRole)
	assert.True(t, hi.Hidden)
	assert.Equal(t, int64(3600), hi.DelaySecs)

	config := []oplog.Member{{Host: "c:1", Set: "cfg", State: "PRIMARY", Self: true, SetRole: "CONFIGSVR"}}
	hi = &hostInfo{NodeType: "replset"}
	setHostRole(hi, config)
	assert.Equal(t, "CONFIGSVR/PRIMARY", hi.ReplRole)
	assert.Nil(t, hi.Priority)

	hi = &hostInfo{NodeType: "replset"}
	setHostRole(hi, walkedSet()[2:])
	assert.Empty(t, hi.ReplRole)

	out, err := formatResults(&collectedInfo{HostInfo: &hostInfo{NodeType: "replset", ReplRole: "SECONDARY (hidden)"}}, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out), fmt.Sprintf("%25s | %s\n", "Process Type", "SECONDARY (hidden)"))

	out, err = formatResults(&collectedInfo{HostInfo: &hostInfo{NodeType: typeMongos}}, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out), fmt.Sprintf("%25s | %s\n", "Process Type", typeMongos))
}

func TestWithEntryFacts(t *testing.T) {
	snap := &snapshot{
		ServerStatus: mustRaw(t, bson.D{
			{Key: "pid", Value: int64(4242)},
			{Key: "storageEngine", Value: bson.D{
				{Key: "name", Value: "wiredTiger"}, {Key: "supportsCommittedReads", Value: true},
				{Key: "persistent", Value: true},
			}},
		}),
		IsMasterRaw: mustRaw(t, bson.D{{Key: "hidden", Value: true}, {Key: "secondaryDelaySecs", Value: int32(60)}}),
	}
	walked := []oplog.Member{{Host: "a:1", Self: true, State: "SECONDARY"}, {Host: "b:1", State: "PRIMARY", Pid: 7}}

	got := withEntryFacts(walked, snap)

	assert.Equal(t, oplog.Member{
		Host: "a:1", Self: true, State: "SECONDARY", Pid: 4242, Engine: wiredTiger, Hidden: true, DelaySecs: 60,
	}, got[0])
	assert.Equal(t, oplog.Member{Host: "b:1", State: "PRIMARY", Pid: 7}, got[1])

	bare := withEntryFacts([]oplog.Member{{Host: "a:1", Self: true}}, &snapshot{})
	assert.Equal(t, oplog.Member{Host: "a:1", Self: true}, bare[0])
}

func TestWithSetRole(t *testing.T) {
	members := []oplog.Member{
		{Host: "a:1", Set: "sh1"},
		{Host: "c:1", Set: "cfg", SetRole: "CONFIGSVR", ViaShardMap: true},
	}

	got := withSetRole(members, "shardsvr")
	assert.Equal(t, "SHARDSVR", got[0].SetRole)
	assert.Equal(t, "CONFIGSVR", got[1].SetRole)

	assert.Empty(t, withSetRole([]oplog.Member{{Host: "a:1"}}, "")[0].SetRole)
}

func TestBuildInstancesKeepsStatus(t *testing.T) {
	status := mustRaw(t, bson.D{
		{Key: "_id", Value: int32(2)}, {Key: "name", Value: "s1:1"}, {Key: "health", Value: 1.0},
		{Key: "state", Value: int32(2)}, {Key: "stateStr", Value: "SECONDARY"}, {Key: "uptime", Value: int32(3600)},
	})

	members, _, _, _ := buildInstances([]oplog.Member{
		{Host: "s1:1", Set: "sh1", State: "SECONDARY", SetRole: "SHARDSVR", Pid: 77, Engine: wiredTiger, Status: status},
	})

	require.Len(t, members, 1)
	assert.Equal(t, int64(77), members[0].ID)
	assert.Equal(t, 1.0, members[0].Health)
	assert.Equal(t, 2.0, members[0].State)
	assert.Equal(t, 3600.0, members[0].Uptime)
	assert.Equal(t, "SHARDSVR/SECONDARY", members[0].StateStr)
	assert.Equal(t, wiredTiger, members[0].StorageEngine)
}

func TestBuildInstancesCountsEntryArbiter(t *testing.T) {
	_, _, read, total := buildInstances([]oplog.Member{
		{Host: "arb:1", Set: "rs", State: "ARBITER", Arbiter: true, Self: true, Pid: 9},
		{Host: "a:1", Set: "rs", State: "PRIMARY"},
		{Host: "arb2:1", Set: "rs", State: "ARBITER", Arbiter: true},
	})

	assert.Equal(t, 1, read)
	assert.Equal(t, 2, total)
}
