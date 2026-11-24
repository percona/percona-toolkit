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
	"bytes"
	"context"
	"io"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/x/bsonx/bsoncore"
	"go.mongodb.org/mongo-driver/x/mongo/driver/wiremessage"
)

func closedAddr(t *testing.T) string {
	t.Helper()

	l, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	require.NoError(t, l.Close())

	return l.Addr().String()
}

func unreachableClient(t *testing.T, addr string, serverSelection time.Duration) (*mongo.Client, *options.ClientOptions) {
	t.Helper()

	co := options.Client().ApplyURI("mongodb://" + addr).
		SetDirect(true).
		SetServerSelectionTimeout(serverSelection)
	client, err := mongo.Connect(context.Background(), co)
	require.NoError(t, err)
	t.Cleanup(func() { _ = client.Disconnect(context.Background()) })

	return client, co
}

func noLoginServer(t *testing.T, hello func(addr string) bson.D, replies map[string]bson.D) string {
	t.Helper()

	l, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	t.Cleanup(func() { _ = l.Close() })

	addr := l.Addr().String()
	raw := map[string][]byte{"": mustRaw(t, append(hello(addr), bson.E{Key: "maxWireVersion", Value: int32(21)},
		bson.E{Key: "ok", Value: 1.0}))}
	for name, reply := range replies {
		raw[name] = mustRaw(t, reply)
	}

	go func() {
		for conn, err := l.Accept(); err == nil; conn, err = l.Accept() {
			go serveNoLogin(conn, raw)
		}
	}()

	return addr
}

func serveNoLogin(conn net.Conn, replies map[string][]byte) {
	defer func() { _ = conn.Close() }()

	header := make([]byte, 16)
	for {
		if _, err := io.ReadFull(conn, header); err != nil {
			return
		}

		length, requestID, _, opcode, _, _ := wiremessage.ReadHeader(header)
		body := make([]byte, max(length-16, 0))
		if _, err := io.ReadFull(conn, body); err != nil {
			return
		}

		name, ok := wireCommandName(opcode, body)
		if !ok {
			return
		}

		reply, ok := replies[name]
		switch {
		case ok:
		case name == "isMaster" || name == "ismaster" || name == "hello":
			reply = replies[""]
		case name == "ping":
			reply = bsoncore.NewDocumentBuilder().AppendDouble("ok", 1).Build()
		default:
			reply = bsoncore.NewDocumentBuilder().AppendDouble("ok", 0).AppendInt32("code", 13).
				AppendString("codeName", "Unauthorized").
				AppendString("errmsg", "command "+name+" requires authentication").Build()
		}

		if _, err := conn.Write(wireReply(opcode, requestID, reply)); err != nil {
			return
		}
	}
}

func wireCommandName(opcode wiremessage.OpCode, body []byte) (string, bool) {
	var doc bsoncore.Document

	switch {
	case opcode == wiremessage.OpMsg:
		_, rem, _ := wiremessage.ReadMsgFlags(body)
		_, rem, _ = wiremessage.ReadMsgSectionType(rem)
		doc, _, _ = wiremessage.ReadMsgSectionSingleDocument(rem)
	case len(body) > 4:
		if end := bytes.IndexByte(body[4:], 0); end >= 0 && 4+end+9 <= len(body) {
			doc, _, _ = bsoncore.ReadDocument(body[4+end+9:])
		}
	}

	first, err := doc.IndexErr(0)
	if err != nil {
		return "", false
	}

	return first.Key(), true
}

func wireReply(opcode wiremessage.OpCode, responseTo int32, doc []byte) []byte {
	if opcode == wiremessage.OpMsg {
		i, wm := wiremessage.AppendHeaderStart(nil, wiremessage.NextRequestID(), responseTo, wiremessage.OpMsg)
		wm = wiremessage.AppendMsgSectionType(wiremessage.AppendMsgFlags(wm, 0), wiremessage.SingleDocument)

		return bsoncore.UpdateLength(append(wm, doc...), i, int32(len(wm[i:])+len(doc)))
	}

	i, wm := wiremessage.AppendHeaderStart(nil, wiremessage.NextRequestID(), responseTo, wiremessage.OpReply)
	wm = wiremessage.AppendReplyFlags(wm, 0)
	wm = wiremessage.AppendReplyCursorID(wm, 0)
	wm = wiremessage.AppendReplyStartingFrom(wm, 0)
	wm = wiremessage.AppendReplyNumberReturned(wm, 1)

	return bsoncore.UpdateLength(append(wm, doc...), i, int32(len(wm[i:])+len(doc)))
}

func fakeClient(t *testing.T, addr string) (*mongo.Client, *options.ClientOptions) {
	t.Helper()

	co := options.Client().ApplyURI("mongodb://" + addr).SetDirect(true).SetServerSelectionTimeout(time.Second)
	client, err := mongo.Connect(context.Background(), co)
	require.NoError(t, err)
	t.Cleanup(func() { _ = client.Disconnect(context.Background()) })

	return client, co
}

func remoteArbiterLab(t *testing.T) (*mongo.Client, *options.ClientOptions, *snapshot, string) {
	t.Helper()

	member := noLoginServer(t, func(addr string) bson.D {
		return bson.D{
			{Key: "ismaster", Value: false}, {Key: "secondary", Value: true}, {Key: "setName", Value: "rs"},
			{Key: "hosts", Value: bson.A{addr}}, {Key: "me", Value: addr},
		}
	}, nil)
	entry := noLoginServer(t, func(addr string) bson.D {
		return bson.D{
			{Key: "ismaster", Value: false}, {Key: "secondary", Value: false}, {Key: "arbiterOnly", Value: true},
			{Key: "setName", Value: "rs"}, {Key: "hosts", Value: bson.A{member}},
			{Key: "arbiters", Value: bson.A{addr}}, {Key: "me", Value: addr},
		}
	}, nil)

	client, co := fakeClient(t, entry)
	snap := takeSnapshot(context.Background(), client)
	require.NoError(t, snap.IsMasterErr)
	require.True(t, snap.IsMaster.IsArbiter())
	for _, err := range []error{snap.HostInfoErr, snap.CmdLineOptsErr, snap.ServerStatusErr} {
		require.ErrorContains(t, err, "requires authentication")
	}

	return client, co, snap, member
}

func TestTakeSnapshotUnreachable(t *testing.T) {
	client, _ := unreachableClient(t, closedAddr(t), 3*time.Second)

	ctx, cancel := newBudget(time.Hour).ctx(context.Background(), 300*time.Millisecond)
	defer cancel()

	start := time.Now()
	snap := takeSnapshot(ctx, client)
	assert.Less(t, time.Since(start), 2*time.Second)

	for _, err := range []error{snap.IsMasterErr, snap.HostInfoErr, snap.CmdLineOptsErr, snap.ServerStatusErr} {
		require.Error(t, err)
		reason, _, _ := classifyError(err, false, "")
		assert.Equal(t, "timed out", reason, err.Error())
	}

	assert.Nil(t, snap.ServerStatus)
	assert.False(t, snap.isMongos())
	assert.Empty(t, snap.clusterRole())
	assert.Empty(t, snap.argv())

	_, ok := snap.maxConns()
	assert.False(t, ok)
	_, ok = snap.serverNow()
	assert.False(t, ok)
}
