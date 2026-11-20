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
	"fmt"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

func TestReportRemoteArbiter(t *testing.T) {
	client, co, snap, member := remoteArbiterLab(t)
	entry := snap.IsMaster.Me

	hi, err := getHostInfo(context.Background(), nil, snap)
	require.NoError(t, err)
	hi.CmdlineArgs = maskArgv(hi.CmdlineArgs)

	opts := &cliOptions{RunningOpsSamples: DefaultRunningOpsSamples, RunningOpsInterval: DefaultRunningOpsInterval}
	ci := collect(context.Background(), client, co, opts, newBudget(time.Minute), snap, hi)

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	text := string(out)

	reason := "accepts no logins; for full details run the tool on its host against localhost"
	note := fmt.Sprintf("%25s | %s", "Arbiter", reason)
	for _, want := range []string{
		"# This host", "Hostname | " + entry, "Process Type | ARBITER", "ReplSet | rs", "# Arbiter",
		"no oplog on an arbiter", "\n       " + member + " ",
	} {
		assert.Contains(t, text, want)
	}
	assert.Equal(t, "\n"+header("Not collected")+"\n"+note+"\n", sectionBetweenHeaders(text, "Not collected"))
	assert.LessOrEqual(t, utf8.RuneCountInString(note), headerWidth)
	assert.Equal(t, 1, strings.Count(text, reason))
	oplogRow := lineContaining(sectionBetweenHeaders(text, "Oplog"), member)
	assert.True(t, strings.HasSuffix(oplogRow, "SECONDARY  no login: pass --username/--password"), oplogRow)
	assert.Contains(t, text, "mongos and oplog details are not collected from it.\n\n"+header("Oplog")+"\n")
	assertSectionSpacing(t, text, "remote arbiter")

	for _, unwanted := range []string{
		"# OS & Production Checks", "# Command line arguments", "# Startup Options", "# Running Ops",
		"# WiredTiger", "# Memory", "# Connections & Profiling", "# Security", "# Change Streams",
		"# Database Inventory", "# Mongos", "# Shards", "Host facts", "Server status", "Version |", "FCV |",
		"Started |", "     0 " + member, "&#",
	} {
		assert.NotContains(t, text, unwanted)
	}

	assert.Equal(t, []collectError{{Section: "Arbiter", Item: "Arbiter", Reason: reason}}, ci.Errors)

	js, err := formatResults(ci, "json")
	require.NoError(t, err)
	require.True(t, json.Valid(js))

	var doc struct {
		HostInfo         *hostInfo
		SecuritySettings *security
		RunningOps       *opCounters
		OplogInfo        []proto.OplogInfo
		Errors           []collectError
	}
	require.NoError(t, json.Unmarshal(js, &doc))
	assert.True(t, doc.HostInfo.IsArbiter)
	assert.Nil(t, doc.SecuritySettings)
	assert.Nil(t, doc.RunningOps)
	assert.Equal(t, []collectError{{Section: "Arbiter", Item: "Arbiter", Reason: reason}}, doc.Errors)

	byHost := map[string]proto.OplogInfo{}
	for _, r := range doc.OplogInfo {
		byHost[r.Hostname] = r
	}
	assert.Equal(t, "no login: pass --username/--password", byHost[member].Error)
	assert.Equal(t, "(Unauthorized) command aggregate requires authentication", byHost[member].ErrorDetail)
	assert.Equal(t, "no oplog on an arbiter", byHost[entry].Error)
	assert.Empty(t, byHost[entry].ErrorDetail)
}
