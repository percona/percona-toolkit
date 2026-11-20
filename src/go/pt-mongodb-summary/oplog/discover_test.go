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
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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
	rows := GetOplogInfo(ctx, nil, co, members, 4, 5*time.Second)
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
	rows = GetOplogInfo(expired, nil, co, members[:1], 4, 5*time.Second)
	require.Len(t, rows, 1)
	assert.Equal(t, "timed out", rows[0].Error)
	assert.Equal(t, context.DeadlineExceeded.Error(), rows[0].ErrorDetail)
}

type fakeRead struct {
	mu    sync.Mutex
	calls []string
	peers map[string][]Member
	fn    func(ctx context.Context, m Member, row *proto.OplogInfo) error
}

func (f *fakeRead) read(ctx context.Context, m Member, row *proto.OplogInfo) ([]Member, error) {
	f.mu.Lock()
	f.calls = append(f.calls, m.Host)
	f.mu.Unlock()

	return f.peers[m.Host], f.fn(ctx, m, row)
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
