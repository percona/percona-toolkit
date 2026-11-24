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
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/oplog"
)

var (
	lastEntry = time.Date(2026, 11, 3, 9, 12, 44, 0, time.UTC)
	elected   = time.Date(2026, 10, 27, 18, 11, 52, 0, time.UTC)
)

func oplogRow(host, set, state string, days float64) proto.OplogInfo {
	r := proto.OplogInfo{
		Hostname:   host,
		ReplicaSet: set,
		State:      state,
		Size:       14 << 20,
		UsedMB:     14,
		MaxSizeMB:  990,
		TLast:      lastEntry,
		Now:        lastEntry.Add(time.Second),
	}
	r.TFirst = r.TLast.Add(-time.Duration(days * 24 * float64(time.Hour)))
	r.TimeDiff = r.TLast.Sub(r.TFirst)
	r.TimeDiffHours = r.TimeDiff.Hours()
	r.Running = fmt.Sprintf("%0.2f days", r.TimeDiffHours/24)

	return r
}

func errorRow(host, set, state, reason string) proto.OplogInfo {
	return proto.OplogInfo{Hostname: host, ReplicaSet: set, State: state, Error: reason}
}

func mockupRows() []proto.OplogInfo {
	primary := oplogRow("localhost:37019", "replset", "PRIMARY", 6.46)
	primary.Primary = "localhost:37019"
	primary.ElectionTime = elected
	primary.ElectionReason = "priorityTakeover"

	secondary := oplogRow("localhost:37018", "replset", "SECONDARY", 6.36)
	secondary.Size, secondary.UsedMB = 13<<20, 13
	secondary.Primary = "localhost:37019"
	secondary.ElectionTime = elected

	return []proto.OplogInfo{
		errorRow("localhost:37021", "replset", "SECONDARY", "not authorized to read local.oplog.rs"),
		primary,
		errorRow("localhost:37020", "replset", "ARBITER", "no oplog on an arbiter"),
		secondary,
	}
}

func TestOpLogsSort(t *testing.T) {
	rows := proto.OpLogs{
		errorRow("err", "rs", "SECONDARY", "timed out"),
		oplogRow("long", "rs", "SECONDARY", 3),
		{Hostname: "empty"},
		oplogRow("short", "rs", "PRIMARY", 1),
		oplogRow("short2", "rs", "SECONDARY", 1),
		errorRow("arb", "rs", "ARBITER", "no oplog on an arbiter"),
	}
	sort.Stable(rows)

	var hosts []string
	for _, r := range rows {
		hosts = append(hosts, r.Hostname)
	}
	assert.Equal(t, []string{"short", "short2", "long", "err", "empty", "arb"}, hosts)

	assert.True(t, rows[0].HasData())
	assert.False(t, proto.OplogInfo{}.HasData())
	assert.False(t, proto.OplogInfo{TLast: lastEntry, Error: "timed out"}.HasData())
}

func TestGroupOplogInfo(t *testing.T) {
	rows := mockupRows()

	sh1 := oplogRow("sh1-b:27018", "sh1", "SECONDARY", 2)
	rows = append(rows, errorRow("sh1-a:27018", "sh1", "", "timed out"), sh1)
	rows = append(rows, errorRow("sh2-a:27018", "sh2", "DOWN", "unreachable from this host"))

	hidden := oplogRow("cfg-b:27019", "cfg", "SECONDARY", 5)
	recovering := oplogRow("cfg-a:27019", "cfg", "RECOVERING", 1)
	rows = append(rows, hidden, recovering)

	sets := groupOplogInfo(rows)

	var names []string
	for _, s := range sets {
		names = append(names, s.Name)
	}
	require.Equal(t, []string{"cfg", "replset", "sh1", "sh2"}, names)

	cfg, rs, s1, s2 := sets[0], sets[1], sets[2], sets[3]

	var hosts []string
	for _, m := range rs.Members {
		hosts = append(hosts, m.Hostname)
	}
	assert.Equal(t, []string{"localhost:37018", "localhost:37019", "localhost:37020", "localhost:37021"}, hosts)
	assert.Equal(t, "localhost:37019", rs.Primary)
	assert.Equal(t, "2026-10-27 18:11:52 UTC", rs.LastElection)
	assert.Equal(t, "priorityTakeover", rs.ElectionReason)
	require.NotNil(t, rs.Shortest)
	require.NotNil(t, rs.Longest)
	assert.Equal(t, "localhost:37018", rs.Shortest.Hostname)
	assert.Equal(t, "localhost:37019", rs.Longest.Hostname)
	assert.Equal(t, len("localhost:37018"), rs.HostWidth)
	assert.Equal(t, len("SECONDARY"), rs.StateWidth)

	assert.Equal(t, "none", s1.Primary)
	assert.Empty(t, s1.LastElection)
	assert.Nil(t, s1.Shortest)
	assert.Nil(t, s1.Longest)

	assert.Equal(t, "unknown", s2.Primary)
	assert.Equal(t, len("State"), groupOplogInfo([]proto.OplogInfo{{ReplicaSet: "x"}})[0].StateWidth)

	assert.Equal(t, "none", cfg.Primary)
	assert.Nil(t, cfg.Shortest, "RECOVERING rows do not count")

	discovered := errorRow("a:1", "rs0", "PRIMARY", "unreachable from this host")
	other := errorRow("b:1", "rs0", "SECONDARY", "unreachable from this host")
	assert.Equal(t, "a:1", groupOplogInfo([]proto.OplogInfo{other, discovered})[0].Primary)

	same := []proto.OplogInfo{oplogRow("a:1", "rs0", "PRIMARY", 2), oplogRow("b:1", "rs0", "SECONDARY", 2)}
	set := groupOplogInfo(same)[0]
	assert.Equal(t, "a:1", set.Shortest.Hostname)
	assert.Equal(t, "b:1", set.Longest.Hostname)

	assert.Empty(t, groupOplogInfo(nil))
}

func TestOplogTableLongHost(t *testing.T) {
	long := strings.Repeat("mongodb-rs0-0.mongodb-rs0.ns.svc.", 3)[:74] + ":27017"
	require.Len(t, long, 80)

	hint := "authentication failed; users created via mongos exist only on the config servers; " +
		"create a shard-local user"
	rows := []proto.OplogInfo{
		oplogRow(long, "rs0", "PRIMARY", 1.25),
		oplogRow("short:27017", "rs0", "SECONDARY", 0.5),
		errorRow("other:27017", "rs0", "SECONDARY", hint),
		errorRow("raw:27017", "rs0", "SECONDARY", "failed: "+strings.Repeat("x", 300)),
	}
	rows[1].MaxSizeMB, rows[1].UsedMB, rows[1].Size = 1234567, 1234567, 1234567<<20

	set := groupOplogInfo(rows)[0]
	assert.Equal(t, 60, set.HostWidth)

	out, err := formatResults(&collectedInfo{OplogInfo: rows}, "text")
	require.NoError(t, err)

	section := string(out)[strings.Index(string(out), header("Oplog")):]

	var table, wrapped []string
	for _, line := range strings.Split(section, "\n") {
		assert.LessOrEqual(t, utf8.RuneCountInString(line), 140, line)
		switch {
		case strings.Contains(line, " | "):
		case strings.HasPrefix(line, "   "):
			wrapped = append(wrapped, line)
		case strings.HasPrefix(line, "  "):
			table = append(table, line)
		}
	}
	require.Len(t, table, 5)
	assert.NotEmpty(t, wrapped)

	stateCol := utf8.RuneCountInString(table[0][:strings.Index(table[0], "State")])
	assert.Equal(t, 2+60+2, stateCol)
	for _, line := range table[1:] {
		runes := []rune(line)
		assert.Equal(t, ' ', runes[stateCol-1], line)
		assert.NotEqual(t, ' ', runes[stateCol], line)
	}
	reasonCol := stateCol + len("SECONDARY") + 2
	for _, line := range wrapped {
		runes := []rune(line)
		assert.Equal(t, strings.Repeat(" ", reasonCol), string(runes[:reasonCol]), line)
		assert.NotEqual(t, ' ', runes[reasonCol], line)
	}

	cut := []rune(table[1])[2 : 2+60]
	assert.Contains(t, string(cut), "…")
	assert.True(t, strings.HasPrefix(string(cut), "mongodb-rs0-0.mongodb-rs0"), string(cut))
	assert.True(t, strings.HasSuffix(string(cut), ":27017"), string(cut))

	assert.Contains(t, string(out), "create a shard-local user")
	assert.Contains(t, string(out), "x…")

	end := utf8.RuneCountInString(table[0][:strings.Index(table[0], "Max MB")+len("Max MB")])
	data := 0
	for _, line := range table[1:] {
		if !strings.HasSuffix(line, "2026-11-03 09:12:44") {
			continue
		}
		data++
		runes := []rune(line)
		assert.NotEqual(t, ' ', runes[end-1], "Max MB right-aligned: %q", line)
		assert.Equal(t, ' ', runes[end], line)
	}
	assert.Equal(t, 2, data)
}

func TestFormatOplog(t *testing.T) {
	ci := &collectedInfo{OplogInfo: mockupRows()}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	text := string(out)

	assert.Contains(t, text, "\n"+header("Oplog")+"\n")
	for _, want := range []string{
		fmt.Sprintf("%25s | %s\n", "Replica Set", "replset"),
		fmt.Sprintf("%25s | %s\n", "Primary", "localhost:37019"),
		fmt.Sprintf("%25s | %s\n", "Last Election", "2026-10-27 18:11:52 UTC (priorityTakeover)"),
		"  Host             State      Max MB  Used MB  Used%     Window  Last Entry (UTC)\n",
		"  localhost:37018  SECONDARY     990       13   1.3%  6.36 days  2026-11-03 09:12:44\n",
		"  localhost:37019  PRIMARY       990       14   1.4%  6.46 days  2026-11-03 09:12:44\n",
		"  localhost:37020  ARBITER    no oplog on an arbiter\n",
		"  localhost:37021  SECONDARY  not authorized to read local.oplog.rs\n",
		fmt.Sprintf("%25s | %s\n", "Shortest Window", "localhost:37018 (6.36 days)"),
		fmt.Sprintf("%25s | %s\n", "Longest Window", "localhost:37019 (6.46 days)"),
	} {
		assert.Contains(t, text, want)
	}
	for _, unwanted := range []string{"&#43;", " Mb", "&#", "Oplog Size"} {
		assert.NotContains(t, text, unwanted)
	}
	assert.Regexp(t, `Last Election \| 2026-`, text)

	ci.OplogInfo = append(ci.OplogInfo, errorRow("sh1-a:27018", "sh1", "", "timed out"))
	out, err = formatResults(ci, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out), "localhost:37019 (6.46 days)\n\n"+fmt.Sprintf("%25s | %s\n", "Replica Set", "sh1"))
	assert.Contains(t, string(out), fmt.Sprintf("%25s | %s\n", "Primary", "unknown"))
	assert.Contains(t, string(out), "  sh1-a:27018         timed out\n")

	js, err := formatResults(ci, "json")
	require.NoError(t, err)

	var decoded struct{ OplogInfo []map[string]any }
	require.NoError(t, json.Unmarshal(js, &decoded))
	require.Len(t, decoded.OplogInfo, 5)
	for _, key := range []string{
		"Hostname", "Size", "UsedMB", "TimeDiff", "TimeDiffHours", "Running", "TFirst", "TLast", "Now",
		"ElectionTime", "ReplicaSet", "State", "MaxSizeMB", "Primary", "ElectionReason", "Error",
	} {
		assert.Contains(t, decoded.OplogInfo[0], key)
	}
}

func remoteArbiterSnapshot(t *testing.T, entry, member string) *snapshot {
	t.Helper()

	denied := func(cmd string) error {
		return fmt.Errorf("command %s requires authentication", cmd)
	}
	snap := &snapshot{
		IsMasterRaw: mustRaw(t, bson.D{
			{Key: "setName", Value: "rs"},
			{Key: "hosts", Value: bson.A{member}},
			{Key: "arbiters", Value: bson.A{entry}},
			{Key: "arbiterOnly", Value: true},
			{Key: "me", Value: entry},
			{Key: "ok", Value: 1.0},
		}),
		HostInfoErr:     denied("hostInfo"),
		CmdLineOptsErr:  denied("getCmdLineOpts"),
		ServerStatusErr: denied("serverStatus"),
	}
	require.NoError(t, bson.Unmarshal(snap.IsMasterRaw, &snap.IsMaster))

	return snap
}

func TestMemberPhaseUnreachable(t *testing.T) {
	entry, member := closedAddr(t), closedAddr(t)
	client, co := unreachableClient(t, entry, 100*time.Millisecond)
	snap := remoteArbiterSnapshot(t, entry, member)
	g := &gaps{isArbiter: true}

	start := time.Now()
	members, details, rows := memberPhase(context.Background(), client, co, snap, newArbiterHostInfo(snap.IsMaster),
		newBudget(time.Minute), g)
	assert.Less(t, time.Since(start), 3*time.Second)

	want := []proto.Members{
		{Name: entry, StateStr: "ARBITER", Set: "rs"},
		{Name: member, Set: "rs"},
	}
	sort.Slice(want, func(i, j int) bool { return want[i].Name < want[j].Name })
	assert.Equal(t, want, members)
	assert.Equal(t, []memberDetail{{Host: want[0].Name}, {Host: want[1].Name}}, details)

	require.Len(t, rows, 2)
	byHost := map[string]proto.OplogInfo{}
	for _, r := range rows {
		byHost[r.Hostname] = r
	}
	assert.Equal(t, "no oplog on an arbiter", byHost[entry].Error)
	assert.Equal(t, "ARBITER", byHost[entry].State)
	assert.Equal(t, "unreachable from this host", byHost[member].Error)

	assert.Equal(t, "ARBITER", g.memberState)
	require.Len(t, g.list, 1)
	assert.Equal(t, "Instances", g.list[0].Section)

	out, err := formatResults(&collectedInfo{ReplicaMembers: members, OplogInfo: rows, Errors: g.list}, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out), "# Instances")
	assert.Contains(t, string(out), fmt.Sprintf("%25s | %s\n", "Primary", "unknown"))
}

func TestMemberPhaseBudget(t *testing.T) {
	entry, member := closedAddr(t), closedAddr(t)
	client, co := unreachableClient(t, entry, 30*time.Second)
	snap := remoteArbiterSnapshot(t, entry, member)
	g := &gaps{isArbiter: true}

	start := time.Now()
	_, _, rows := memberPhase(context.Background(), client, co, snap, newArbiterHostInfo(snap.IsMaster),
		newBudget(500*time.Millisecond), g)
	assert.Less(t, time.Since(start), 2*time.Second)

	for _, r := range rows {
		assert.NotEmpty(t, r.Error, r.Hostname)
	}
}

func TestAddInstancesGap(t *testing.T) {
	hook := logtest.NewGlobal()
	defer hook.Reset()

	const needs = "replSetGetStatus: clusterMonitor"
	members := []proto.Members{
		{Name: "localhost:37020", StateStr: "ARBITER", Set: "rs", ID: 7},
		{Name: "localhost:37018", StateStr: "PRIMARY", Set: "rs"},
		{Name: "localhost:37019", Set: "rs"},
		{Name: "localhost:37021", Set: "rs"},
	}
	partial := collectError{Section: "Instances", Item: "Instances", Reason: "partial: 1 of 4 members read"}

	tests := []struct {
		name    string
		arbiter bool
		level   log.Level
	}{
		{"arbiter", true, log.InfoLevel},
		{"data node", false, log.WarnLevel},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hook.Reset()
			g := &gaps{isArbiter: tt.arbiter}

			addInstancesGap(g, tt.arbiter, false, needs, nil, members, 1, 4)
			assert.Equal(t, []collectError{partial}, g.list)
			require.Len(t, hook.AllEntries(), 1)
			assert.Equal(t, tt.level, hook.LastEntry().Level)
			assert.Contains(t, hook.LastEntry().Message, "cannot get Instances: partial: 1 of 4 members read")

			hook.Reset()
			g = &gaps{isArbiter: tt.arbiter}
			addInstancesGap(g, tt.arbiter, false, needs, nil, members, 4, 4)
			assert.Empty(t, g.list)
			assert.Empty(t, hook.AllEntries())

			addInstancesGap(g, tt.arbiter, false, needs, nil, nil, 0, 0)
			assert.Equal(t, []collectError{{Section: "Instances", Item: "Instances", Reason: "no members found"}}, g.list)
			require.Len(t, hook.AllEntries(), 1)
			assert.Equal(t, log.WarnLevel, hook.LastEntry().Level)
		})
	}

	hook.Reset()
	g := &gaps{}
	addInstancesGap(g, false, false, needs, errors.New("connection reset by peer"), members, 1, 4)
	assert.Equal(t, []collectError{{Section: "Instances", Item: "Instances", Reason: "connection reset by peer"}}, g.list)
	require.Len(t, hook.AllEntries(), 1)
	assert.Equal(t, log.WarnLevel, hook.LastEntry().Level)

	noLogin := errors.New("cannot getShardMap for GetHostnames: (Unauthorized) " +
		"command getShardMap requires authentication")

	hook.Reset()
	g = &gaps{isArbiter: true}
	addInstancesGap(g, true, true, needs, noLogin, members, 0, 4)
	assert.Empty(t, g.list)
	require.Len(t, hook.AllEntries(), 1)
	assert.Equal(t, log.InfoLevel, hook.LastEntry().Level)

	addInstancesGap(g, true, false, needs, noLogin, members, 0, 4)
	assert.Equal(t, []collectError{{Section: "Instances", Item: "Instances", Reason: remoteArbiterReason}}, g.list)

	hook.Reset()
	g = &gaps{isArbiter: true}
	addInstancesGap(g, true, true, needs, nil, members, 0, 3)
	assert.Empty(t, g.list)
	require.Len(t, hook.AllEntries(), 1)
	assert.Equal(t, log.InfoLevel, hook.LastEntry().Level)
	assert.Contains(t, hook.LastEntry().Message, "partial: 0 of 3 members read")

	g = &gaps{isArbiter: true}
	addInstancesGap(g, true, true, needs, errors.New("connection reset by peer"), members, 0, 4)
	assert.Equal(t, []collectError{{Section: "Instances", Item: "Instances", Reason: "connection reset by peer"}}, g.list)
}

func TestSelfState(t *testing.T) {
	assert.Equal(t, "SECONDARY", selfState([]oplog.Member{
		{Host: "a", State: "PRIMARY"},
		{Host: "b", State: "SECONDARY", Self: true},
	}))
	assert.Empty(t, selfState([]oplog.Member{{Host: "a", State: "PRIMARY"}}))
	assert.Empty(t, selfState(nil))
}

func TestMemberPhaseReplStatusDenied(t *testing.T) {
	denied := func(cmd string) bson.D {
		return bson.D{
			{Key: "ok", Value: 0.0}, {Key: "code", Value: int32(13)}, {Key: "codeName", Value: "Unauthorized"},
			{Key: "errmsg", Value: "not authorized on admin to execute command { " + cmd + ": 1 }"},
		}
	}
	addr := noLoginServer(t, func(addr string) bson.D {
		return bson.D{
			{Key: "ismaster", Value: true}, {Key: "setName", Value: "rs"},
			{Key: "hosts", Value: bson.A{addr}}, {Key: "me", Value: addr},
		}
	}, map[string]bson.D{"replSetGetStatus": denied("replSetGetStatus"), "getShardMap": denied("getShardMap")})

	client, co := fakeClient(t, addr)
	snap := takeSnapshot(context.Background(), client)
	require.NoError(t, snap.IsMasterErr)
	g := &gaps{}

	members, _, _ := memberPhase(context.Background(), client, co, snap, &hostInfo{NodeType: "replset"},
		newBudget(time.Minute), g)

	require.Len(t, members, 1)
	assert.Equal(t, []collectError{{
		Section: "Instances", Item: "Instances", Code: 13,
		Reason: "not authorized (needs replSetGetStatus: clusterMonitor)",
	}}, g.list)
}
