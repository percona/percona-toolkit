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
	"fmt"
	"sync"
	"testing"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/x/mongo/driver"
)

func TestGapsClassify(t *testing.T) {
	unauthorized := mongo.CommandError{
		Code:    13,
		Name:    "Unauthorized",
		Message: "not authorized on admin to execute command { getLog: \"startupWarnings\" }",
	}
	remoteArbiter := mongo.CommandError{Code: 13, Name: "Unauthorized", Message: "command serverStatus requires authentication"}
	directShard := mongo.CommandError{
		Code: 13,
		Name: "Unauthorized",
		Message: "You are connecting to a sharded cluster improperly by connecting directly to a shard. " +
			"Please connect to the cluster via a router (mongos).",
	}
	handshake := fmt.Errorf("connection() error occurred during connection handshake: auth error: %w",
		driver.Error{Code: 18, Name: "AuthenticationFailed", Message: "Authentication failed."})

	tests := []struct {
		name      string
		err       error
		isArbiter bool
		needs     string
		reason    string
		code      int32
		expected  bool
	}{
		{"denied on a data node", unauthorized, false, "getLog: clusterMonitor",
			"not authorized (needs getLog: clusterMonitor)", 13, false},
		{"denied, needs unknown", errors.Wrap(unauthorized, "getLog"), false, "",
			"not authorized", 13, false},
		{"user counts", unauthorized, false, "find on admin.system.users",
			"not authorized (needs find on admin.system.users)", 13, true},
		{"cluster parameter", unauthorized, false, "getClusterParameter: clusterManager",
			"not authorized (needs getClusterParameter: clusterManager)", 13, true},
		{"config system collections", unauthorized, false, "collStats on config system collections",
			"not authorized (needs collStats on config system collections)", 13, true},
		{"remote arbiter", remoteArbiter, true, "serverStatus: clusterMonitor",
			"arbiter accepts no logins; run the tool on the arbiter host against localhost", 13, true},
		{"arbiter over localhost", unauthorized, true, "getLog: clusterMonitor",
			"arbiter accepts no logins", 13, true},
		{"requires authentication on a data node", remoteArbiter, false, "serverStatus: clusterMonitor",
			"not authorized (needs serverStatus: clusterMonitor)", 13, false},
		{"direct shard connection", directShard, false, "listDatabases: clusterMonitor",
			"connect through mongos", 13, true},
		{"member state", mongo.CommandError{Code: 13436, Name: "NotPrimaryOrSecondary"}, false, "",
			"unavailable in this member state", 13436, true},
		{"deadline", context.DeadlineExceeded, false, "", "timed out", 0, false},
		{"wrapped deadline", errors.Wrap(context.DeadlineExceeded, "getLog"), true, "", "timed out", 0, false},
		{"max time expired", mongo.CommandError{Code: 50, Name: "MaxTimeMSExpired"}, false, "", "timed out", 50, false},
		{"authentication failed", handshake, false, "", "authentication failed", 18, false},
		{"other error", errors.New("connection reset by peer"), false, "hostInfo: clusterMonitor",
			"connection reset by peer", 0, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			reason, code, expected := classifyError(tt.err, tt.isArbiter, tt.needs)
			assert.Equal(t, tt.reason, reason)
			assert.Equal(t, tt.code, code)
			assert.Equal(t, tt.expected, expected)
		})
	}
}

func TestGapsAdd(t *testing.T) {
	g := &gaps{isArbiter: true}
	g.add("Running Ops", "Running Ops", "serverStatus: clusterMonitor",
		mongo.CommandError{Code: 13, Message: "command serverStatus requires authentication"})
	g.add("Security", "Users/Roles", "", nil)

	assert.Equal(t, []collectError{{
		Section: "Running Ops",
		Item:    "Running Ops",
		Code:    13,
		Reason:  "arbiter accepts no logins; run the tool on the arbiter host against localhost",
	}}, g.list)

	g = &gaps{}
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			g.add("Oplog", "Oplog", "", context.DeadlineExceeded)
		}()
	}
	wg.Wait()
	assert.Len(t, g.list, 20)
}

func TestGapsNote(t *testing.T) {
	hook := logtest.NewGlobal()
	defer hook.Reset()

	g := &gaps{isArbiter: true}
	g.note("Arbiter", "Arbiter", remoteArbiterReason, true)
	require.Len(t, hook.AllEntries(), 1)
	assert.Equal(t, log.InfoLevel, hook.LastEntry().Level)
	assert.Contains(t, hook.LastEntry().Message, "cannot get Arbiter: "+remoteArbiterReason)

	g.note("Oplog", "Oplog", "no oplog collection", false)
	require.Len(t, hook.AllEntries(), 2)
	assert.Equal(t, log.WarnLevel, hook.LastEntry().Level)
	assert.Contains(t, hook.LastEntry().Message, "[Warning] cannot get Oplog: no oplog collection")

	assert.Equal(t, []collectError{
		{Section: "Arbiter", Item: "Arbiter", Reason: remoteArbiterReason},
		{Section: "Oplog", Item: "Oplog", Reason: "no oplog collection"},
	}, g.list)
}

func TestGapsMemberState(t *testing.T) {
	hook := logtest.NewGlobal()
	defer hook.Reset()

	notPrimary := mongo.CommandError{
		Code:    13436,
		Name:    "NotPrimaryOrSecondary",
		Message: "node is not in primary or recovering state",
	}

	g := &gaps{}
	g.add("Database Inventory", "Database Inventory", "listDatabases: clusterMonitor", notPrimary)
	g.setMemberState("STARTUP2")
	g.add("Database Inventory", "Database Inventory", "listDatabases: clusterMonitor", notPrimary)
	g.add("Security", "Users/Roles", "find on admin.system.users", mongo.CommandError{Code: 13, Name: "Unauthorized"})

	assert.Equal(t, []collectError{
		{Section: "Database Inventory", Item: "Database Inventory", Code: 13436, Reason: "unavailable in this member state"},
		{Section: "Database Inventory", Item: "Database Inventory", Code: 13436, Reason: "unavailable in member state STARTUP2"},
		{Section: "Security", Item: "Users/Roles", Code: 13, Reason: "not authorized (needs find on admin.system.users)"},
	}, g.list)
	for _, e := range hook.AllEntries() {
		assert.Equal(t, log.InfoLevel, e.Level, e.Message)
	}

	var wg sync.WaitGroup
	for _, state := range []string{"SECONDARY", "RECOVERING", "ROLLBACK"} {
		wg.Add(2)
		go func() {
			defer wg.Done()
			g.setMemberState(state)
		}()
		go func() {
			defer wg.Done()
			g.add("Oplog", "Oplog", "", notPrimary)
		}()
	}
	wg.Wait()
	assert.Len(t, g.list, 6)
}
