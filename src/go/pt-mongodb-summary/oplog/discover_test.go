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

package oplog

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/x/mongo/driver"
	"go.mongodb.org/mongo-driver/x/mongo/driver/topology"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

func TestDescribeError(t *testing.T) {
	handshake := fmt.Errorf("connection() error occurred during connection handshake: auth error: %w",
		driver.Error{Code: 18, Name: "AuthenticationFailed", Message: "Authentication failed."})
	selection := topology.ServerSelectionError{Wrapped: context.DeadlineExceeded}

	tests := []struct {
		name        string
		err         error
		viaShardMap bool
		want        string
	}{
		{"no error", nil, false, ""},
		{"unauthorized", mongo.CommandError{Code: 13, Name: "Unauthorized", Message: "not authorized on local"}, false,
			"not authorized to read local.oplog.rs"},
		{"requires authentication", mongo.CommandError{Code: 13, Message: "command find requires authentication"}, true,
			"no login: pass --username/--password"},
		{"wrapped requires authentication", fmt.Errorf("aggregate: %w",
			mongo.CommandError{Code: 13, Name: "Unauthorized", Message: "command aggregate requires authentication"}), false,
			"no login: pass --username/--password"},
		{"authentication failed", handshake, false, "authentication failed"},
		{"authentication failed via mongos", handshake, true,
			"authentication failed; users created via mongos exist only on the config servers; create a shard-local user"},
		{"authentication failed command", mongo.CommandError{Code: 18, Name: "AuthenticationFailed"}, false,
			"authentication failed"},
		{"unreachable", selection, false, "unreachable from this host"},
		{"wrapped unreachable", fmt.Errorf("ping: %w", selection), true, "unreachable from this host"},
		{"deadline", context.DeadlineExceeded, false, "timed out"},
		{"max time", mongo.CommandError{Code: 50, Name: "MaxTimeMSExpired"}, false, "timed out"},
		{"namespace not found", mongo.CommandError{Code: 26, Name: "NamespaceNotFound"}, false, "no oplog collection"},
		{"collStats not found", mongo.CommandError{Code: 40280}, false, "no oplog collection"},
		{"no collStats result", errNoCollStats, false, "no oplog collection"},
		{"empty oplog", mongo.ErrNoDocuments, false, "oplog is empty"},
		{"other command error", mongo.CommandError{Code: 11600, Name: "InterruptedAtShutdown"}, false,
			"failed: InterruptedAtShutdown"},
		{"other error", fmt.Errorf("socket was unexpectedly closed: EOF"), false,
			"failed: socket was unexpectedly closed: EOF"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := describeError(tt.err, tt.viaShardMap)
			assert.Equal(t, tt.want, got)
			if strings.HasPrefix(tt.name, "other") {
				return
			}
			assert.NotContainsf(t, got, `"`, "%q", got)
			for _, c := range []string{"<", ">", "&", "+"} {
				assert.NotContains(t, got, c)
			}
		})
	}
}

func closedAddr(t *testing.T) string {
	t.Helper()

	l, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	require.NoError(t, l.Close())

	return l.Addr().String()
}

func TestGetOplogInfoUnreachable(t *testing.T) {
	addr := closedAddr(t)
	co := options.Client().ApplyURI("mongodb://" + addr).SetServerSelectionTimeout(30 * time.Second)

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	members := []Member{
		{Host: addr, Set: "rs", State: "SECONDARY"},
		{Host: "arbiter.invalid:27017", Set: "rs", State: "ARBITER (down)", Arbiter: true},
	}

	start := time.Now()
	rows, _ := GetOplogInfo(ctx, nil, co, members, 4, 5*time.Second)
	assert.Less(t, time.Since(start), 2*time.Second)

	require.Len(t, rows, 2)
	assert.Contains(t, rows[0].ErrorDetail, "server selection")
	assert.Equal(t, proto.OplogInfo{
		Hostname:    addr,
		ReplicaSet:  "rs",
		State:       "SECONDARY",
		Error:       "unreachable from this host",
		ErrorDetail: rows[0].ErrorDetail,
	}, rows[0])
	assert.Equal(t, proto.OplogInfo{
		Hostname:   "arbiter.invalid:27017",
		ReplicaSet: "rs",
		State:      "ARBITER (down)",
		Error:      "no oplog on an arbiter",
	}, rows[1])

	expired, cancel := context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
	defer cancel()
	rows, _ = GetOplogInfo(expired, nil, co, members[:1], 4, 5*time.Second)
	require.Len(t, rows, 1)
	assert.Equal(t, "timed out", rows[0].Error)
	assert.Equal(t, context.DeadlineExceeded.Error(), rows[0].ErrorDetail)
}

type fakeRead struct {
	mu    sync.Mutex
	calls []string
	peers map[string][]Member
	found map[string]facts
	fn    func(ctx context.Context, m Member, row *proto.OplogInfo) error
}

func (f *fakeRead) read(ctx context.Context, m Member, row *proto.OplogInfo) (facts, error) {
	f.mu.Lock()
	f.calls = append(f.calls, m.Host)
	f.mu.Unlock()

	res := f.found[m.Host]
	res.peers = f.peers[m.Host]

	return res, f.fn(ctx, m, row)
}

func withData(row *proto.OplogInfo, hours float64) {
	row.TLast = time.Date(2026, 11, 3, 9, 0, 0, 0, time.UTC)
	row.TFirst = row.TLast.Add(-time.Duration(hours * float64(time.Hour)))
	row.TimeDiff = row.TLast.Sub(row.TFirst)
	row.TimeDiffHours = row.TimeDiff.Hours()
}

func TestWalkAuthFailureShortCircuit(t *testing.T) {
	authFailed := fmt.Errorf("auth error: %w", driver.Error{Code: 18, Name: "AuthenticationFailed"})
	f := &fakeRead{fn: func(_ context.Context, m Member, row *proto.OplogInfo) error {
		if m.Set == "sh1" {
			return authFailed
		}
		withData(row, 10)

		return nil
	}}

	members := []Member{
		{Host: "a:1", Set: "sh1", ViaShardMap: true},
		{Host: "b:1", Set: "sh1", ViaShardMap: true},
		{Host: "c:1", Set: "sh1", ViaShardMap: true},
		{Host: "d:1", Set: "sh2", ViaShardMap: true},
		{Host: "e:1", Set: "sh2", Arbiter: true},
	}

	w := &walker{read: f.read, timeout: time.Second}
	rows := w.walk(context.Background(), members, 1)

	assert.Equal(t, []string{"a:1", "d:1"}, f.calls)
	require.Len(t, rows, 5)

	byHost := map[string]proto.OplogInfo{}
	for _, r := range rows {
		byHost[r.Hostname] = r
	}
	assert.Equal(t,
		"authentication failed; users created via mongos exist only on the config servers; create a shard-local user",
		byHost["a:1"].Error)
	assert.Equal(t, authFailed.Error(), byHost["a:1"].ErrorDetail)
	assert.Equal(t, "not tried after authentication failed on a:1", byHost["b:1"].Error)
	assert.Equal(t, "not tried after authentication failed on a:1", byHost["c:1"].Error)
	assert.Empty(t, byHost["b:1"].ErrorDetail)
	assert.Empty(t, byHost["d:1"].Error)
	assert.Empty(t, byHost["d:1"].ErrorDetail)
	assert.Equal(t, "no oplog on an arbiter", byHost["e:1"].Error)
	assert.Empty(t, byHost["e:1"].ErrorDetail)
	assert.Equal(t, "ARBITER", byHost["e:1"].State)
	assert.Equal(t, "d:1", rows[0].Hostname)
}

func TestWalkMemberDeadline(t *testing.T) {
	f := &fakeRead{fn: func(ctx context.Context, _ Member, _ *proto.OplogInfo) error {
		<-ctx.Done()

		return ctx.Err()
	}}

	members := []Member{{Host: "a:1", Set: "rs"}, {Host: "b:1", Set: "rs"}, {Host: "c:1", Set: "rs"}}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	start := time.Now()
	rows := (&walker{read: f.read, timeout: 50 * time.Millisecond}).walk(ctx, members, 1)
	assert.Less(t, time.Since(start), time.Second)
	assert.Len(t, f.calls, 3)
	for _, r := range rows {
		assert.Equal(t, "timed out", r.Error, r.Hostname)
		assert.Equal(t, context.DeadlineExceeded.Error(), r.ErrorDetail, r.Hostname)
	}

	f.calls = nil
	expired, cancel := context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
	defer cancel()
	rows = (&walker{read: f.read, timeout: time.Second}).walk(expired, members, 4)
	assert.Empty(t, f.calls)
	require.Len(t, rows, 3)
	for _, r := range rows {
		assert.Equal(t, "timed out", r.Error, r.Hostname)
	}
}

func TestWalkOrder(t *testing.T) {
	members := []Member{
		{Host: "c1", Set: "cfg"}, {Host: "c2", Set: "cfg"}, {Host: "c3", Set: "cfg"},
		{Host: "a1", Set: "sh1"}, {Host: "a2", Set: "sh1"},
		{Host: "b1", Set: "sh2"},
	}
	assert.Equal(t, []int{0, 3, 5, 1, 4, 2}, walkOrder(members))
	assert.Empty(t, walkOrder(nil))
}

func TestWalkAddsPeers(t *testing.T) {
	f := &fakeRead{
		peers: map[string][]Member{
			"a:1": {
				{Host: "a:1", Set: "sh1", State: "PRIMARY", Self: true},
				{Host: "b:1", Set: "sh1", State: "SECONDARY"},
				{Host: "hidden:1", Set: "sh1", State: "SECONDARY"},
				{Host: "arb:1", Set: "sh1", State: "ARBITER", Arbiter: true},
			},
			"hidden:1": {{Host: "late:1", Set: "sh1", State: "SECONDARY"}},
		},
		fn: func(_ context.Context, _ Member, row *proto.OplogInfo) error {
			withData(row, 10)

			return nil
		},
	}

	members := []Member{{Host: "a:1", Set: "sh1", ViaShardMap: true}, {Host: "b:1", Set: "sh1", ViaShardMap: true}}
	rows := (&walker{read: f.read, timeout: time.Second}).walk(context.Background(), members, 1)

	assert.Equal(t, []string{"a:1", "b:1", "hidden:1"}, f.calls)
	require.Len(t, rows, 4)

	byHost := map[string]proto.OplogInfo{}
	for _, r := range rows {
		byHost[r.Hostname] = r
	}
	assert.Equal(t, "SECONDARY", byHost["hidden:1"].State)
	assert.Equal(t, "sh1", byHost["hidden:1"].ReplicaSet)
	assert.True(t, byHost["hidden:1"].HasData())
	assert.Equal(t, "no oplog on an arbiter", byHost["arb:1"].Error)
	assert.Equal(t, "ARBITER", byHost["arb:1"].State)
	assert.NotContains(t, byHost, "late:1")
	assert.False(t, rows[3].HasData())
}

func TestWalkAuthFailureConcurrent(t *testing.T) {
	authFailed := fmt.Errorf("auth error: %w", driver.Error{Code: 18, Name: "AuthenticationFailed"})
	f := &fakeRead{fn: func(_ context.Context, m Member, row *proto.OplogInfo) error {
		time.Sleep(20 * time.Millisecond)
		if m.Set == "sh1" {
			return authFailed
		}
		withData(row, 10)

		return nil
	}}

	members := []Member{
		{Host: "self:1", Set: "rs", Self: true},
		{Host: "a:1", Set: "sh1", ViaShardMap: true},
		{Host: "b:1", Set: "sh1", ViaShardMap: true},
		{Host: "c:1", Set: "sh1", ViaShardMap: true},
		{Host: "d:1", Set: "sh1", ViaShardMap: true},
	}

	rows := (&walker{read: f.read, timeout: time.Second}).walk(context.Background(), members, 4)

	assert.ElementsMatch(t, []string{"self:1", "a:1"}, f.calls)
	require.Len(t, rows, 5)
	for _, r := range rows[1:] {
		assert.Contains(t, r.Error, "authentication failed", r.Hostname)
	}
	assert.Empty(t, (&walker{read: f.read}).walk(context.Background(), nil, 4))
}

func mustMarshal(t *testing.T, v any) bson.Raw {
	t.Helper()

	b, err := bson.Marshal(v)
	require.NoError(t, err)

	return b
}

func float(v float64) *float64 {
	return &v
}

func TestParseConfig(t *testing.T) {
	doc := mustMarshal(t, bson.D{{Key: "config", Value: bson.D{
		{Key: "_id", Value: "rs"},
		{Key: "members", Value: bson.A{
			bson.D{{Key: "host", Value: "a:1"}, {Key: "priority", Value: 2.0}, {Key: "votes", Value: int32(1)}},
			bson.D{
				{Key: "host", Value: "h:1"}, {Key: "priority", Value: int32(0)}, {Key: "votes", Value: int32(0)},
				{Key: "hidden", Value: true}, {Key: "secondaryDelaySecs", Value: int64(3600)},
			},
			bson.D{{Key: "host", Value: "old:1"}, {Key: "priority", Value: 0.5}, {Key: "votes", Value: int32(1)},
				{Key: "slaveDelay", Value: int32(120)}},
			bson.D{{Key: "priority", Value: 1.0}},
		}},
	}}})

	cfg := parseConfig(doc)

	require.Len(t, cfg, 3)
	assert.Equal(t, Member{Host: "a:1", Priority: float(2), Votes: float(1)}, cfg["a:1"])
	assert.Equal(t, Member{Host: "h:1", Priority: float(0), Votes: float(0), Hidden: true, DelaySecs: 3600}, cfg["h:1"])
	assert.Equal(t, Member{Host: "old:1", Priority: float(0.5), Votes: float(1), DelaySecs: 120}, cfg["old:1"])
	assert.Empty(t, parseConfig(mustMarshal(t, bson.D{{Key: "ok", Value: 1.0}})))
}

func TestMembersFromShardMapSetRole(t *testing.T) {
	doc := mustMarshal(t, bson.D{{Key: "map", Value: bson.D{
		{Key: "config", Value: "cfg/c1:1,c2:1"},
		{Key: "sh1", Value: "sh1/s1:1,s2:1"},
	}}})

	got := map[string]Member{}
	for _, m := range membersFromShardMap(doc) {
		got[m.Host] = m
	}

	require.Len(t, got, 4)
	assert.Equal(t, Member{Host: "c1:1", Set: "cfg", SetRole: "CONFIGSVR", ViaShardMap: true}, got["c1:1"])
	assert.Equal(t, "CONFIGSVR", got["c2:1"].SetRole)
	assert.Equal(t, Member{Host: "s1:1", Set: "sh1", SetRole: "SHARDSVR", ViaShardMap: true}, got["s1:1"])
	assert.Equal(t, "SHARDSVR", got["s2:1"].SetRole)
}

func TestWalkMembers(t *testing.T) {
	f := &fakeRead{
		peers: map[string][]Member{
			"a:1": {
				{Host: "a:1", Set: "rs", State: "PRIMARY", Self: true},
				{Host: "b:1", Set: "rs", State: "SECONDARY"},
				{Host: "arb:1", Set: "rs", State: "ARBITER", Arbiter: true},
			},
		},
		found: map[string]facts{
			"a:1": {config: map[string]Member{
				"a:1":   {Host: "a:1", Priority: float(2), Votes: float(1)},
				"b:1":   {Host: "b:1", Priority: float(1), Votes: float(1), Hidden: true, DelaySecs: 60},
				"arb:1": {Host: "arb:1", Priority: float(0), Votes: float(1)},
			}},
			"b:1": {pid: 202, engine: proto.StorageEngine{Name: "wiredTiger", Persistent: true}},
		},
		fn: func(_ context.Context, m Member, row *proto.OplogInfo) error {
			if m.Host == "b:1" {
				row.State = "SECONDARY"
			}
			withData(row, 10)

			return nil
		},
	}

	members := []Member{{Host: "a:1", Set: "rs", State: "PRIMARY", Self: true, SetRole: "SHARDSVR"}}
	w := &walker{read: f.read, timeout: time.Second}
	rows := w.walk(context.Background(), members, 1)
	got := w.members(members, rows)

	require.Len(t, got, 3)
	byHost := map[string]Member{}
	for _, m := range got {
		byHost[m.Host] = m
	}

	assert.Equal(t, Member{
		Host: "a:1", Set: "rs", State: "PRIMARY", Self: true, SetRole: "SHARDSVR",
		Priority: float(2), Votes: float(1),
	}, byHost["a:1"])
	assert.Equal(t, Member{
		Host: "b:1", Set: "rs", State: "SECONDARY", SetRole: "SHARDSVR", Pid: 202,
		Engine:   proto.StorageEngine{Name: "wiredTiger", Persistent: true},
		Priority: float(1), Votes: float(1), Hidden: true, DelaySecs: 60,
	}, byHost["b:1"])
	assert.Equal(t, Member{
		Host: "arb:1", Set: "rs", State: "ARBITER", Arbiter: true, SetRole: "SHARDSVR",
		Priority: float(0), Votes: float(1),
	}, byHost["arb:1"])
}

func TestMembersFromReplStatusKeepsStatus(t *testing.T) {
	doc := mustMarshal(t, bson.D{
		{Key: "set", Value: "rs"},
		{Key: "members", Value: bson.A{
			bson.D{{Key: "_id", Value: int32(0)}, {Key: "name", Value: "a:1"}, {Key: "stateStr", Value: "PRIMARY"},
				{Key: "state", Value: int32(1)}, {Key: "health", Value: 1.0}, {Key: "uptime", Value: int32(100)}},
		}},
	})

	members := membersFromReplStatus(doc)

	require.Len(t, members, 1)
	uptime, ok := members[0].Status.Lookup("uptime").Int32OK()
	require.True(t, ok)
	assert.Equal(t, int32(100), uptime)
}

func TestWalkMembersStatusFromPeers(t *testing.T) {
	status := mustMarshal(t, bson.D{{Key: "name", Value: "s1:1"}, {Key: "uptime", Value: int32(7)}})
	f := &fakeRead{
		peers: map[string][]Member{"s1:1": {{Host: "s1:1", Set: "sh1", State: "PRIMARY", Self: true, Status: status}}},
		fn:    func(context.Context, Member, *proto.OplogInfo) error { return nil },
	}

	members := []Member{{Host: "s1:1", Set: "sh1", SetRole: "SHARDSVR", ViaShardMap: true}}
	w := &walker{read: f.read, timeout: time.Second}
	got := w.members(members, w.walk(context.Background(), members, 1))

	require.Len(t, got, 1)
	assert.Equal(t, status, got[0].Status)
	assert.True(t, got[0].ViaShardMap)
}

func TestProcessFacts(t *testing.T) {
	pid, engine := processFacts(mustMarshal(t, bson.D{
		{Key: "pid", Value: int64(31)},
		{Key: "storageEngine", Value: bson.D{
			{Key: "name", Value: "wiredTiger"}, {Key: "supportsCommittedReads", Value: true},
			{Key: "readOnly", Value: false}, {Key: "persistent", Value: true},
		}},
	}))

	assert.Equal(t, int64(31), pid)
	assert.Equal(t, proto.StorageEngine{Name: "wiredTiger", SupportsCommittedReads: true, Persistent: true}, engine)

	pid, engine = processFacts(mustMarshal(t, bson.D{{Key: "ok", Value: 1.0}}))
	assert.Zero(t, pid)
	assert.Equal(t, proto.StorageEngine{}, engine)
}

func TestWalkMembersStateFromPeers(t *testing.T) {
	down := mustMarshal(t, bson.D{{Key: "name", Value: "b:1"}, {Key: "health", Value: 0.0}, {Key: "state", Value: int32(8)}})
	f := &fakeRead{
		peers: map[string][]Member{"a:1": {
			{Host: "a:1", Set: "sh1", State: "PRIMARY", Self: true},
			{Host: "b:1", Set: "sh1", State: "DOWN", Status: down},
		}},
		fn: func(_ context.Context, m Member, _ *proto.OplogInfo) error {
			if m.Host == "b:1" {
				return errors.New("connection refused")
			}

			return nil
		},
	}

	members := []Member{{Host: "a:1", Set: "sh1", ViaShardMap: true}, {Host: "b:1", Set: "sh1", ViaShardMap: true}}
	w := &walker{read: f.read, timeout: time.Second}
	got := w.members(members, w.walk(context.Background(), members, 1))

	require.Len(t, got, 2)
	assert.Equal(t, "DOWN", got[1].State)
	assert.Equal(t, down, got[1].Status)
}
