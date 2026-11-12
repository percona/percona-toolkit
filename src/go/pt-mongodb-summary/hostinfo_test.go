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
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDescribeFCV(t *testing.T) {
	tests := []struct {
		fcv    *fcvInfo
		binary string
		want   string
	}{
		{nil, "7.0.14-8", ""},
		{&fcvInfo{}, "7.0.14-8", ""},
		{&fcvInfo{Version: "7.0"}, "7.0.14-8", "7.0"},
		{&fcvInfo{Version: "7.0"}, "", "7.0"},
		{&fcvInfo{Version: "6.0"}, "7.0.14-8", "6.0 (binary is 7.0)"},
		{&fcvInfo{Version: "6.0", TargetVersion: "7.0"}, "7.0.14-8", "6.0 (upgrading to 7.0)"},
		{&fcvInfo{Version: "6.0", TargetVersion: "6.0", PreviousVersion: "7.0"}, "7.0.14-8", "6.0 (downgrading from 7.0)"},
		{&fcvInfo{Version: "4.0", TargetVersion: "4.0"}, "4.2.25", "4.0 (downgrading from 4.2)"},
		{&fcvInfo{Version: "4.2", TargetVersion: "4.2"}, "4.4.29-28", "4.2 (downgrading from 4.4)"},
		{&fcvInfo{Version: "4.0", TargetVersion: "4.2"}, "4.2.25", "4.0 (upgrading to 4.2)"},
		{&fcvInfo{Version: "4.0", TargetVersion: "4.0"}, "", "4.0 (downgrading)"},
		{&fcvInfo{Version: "3.4"}, "3.6.23", "3.4 (binary is 3.6)"},
		{&fcvInfo{Version: "8.0"}, "8.0", "8.0"},
	}

	for _, tt := range tests {
		assert.Equal(t, tt.want, describeFCV(tt.fcv, tt.binary), "%+v %s", tt.fcv, tt.binary)
	}

	hi := &hostInfo{Version: "7.0.14-8", FCV: &fcvInfo{Version: "6.0"}}
	assert.Equal(t, "6.0 (binary is 7.0)", hi.FCVSummary())
	assert.Empty(t, (&hostInfo{}).FCVSummary())
}

func TestFillFCV(t *testing.T) {
	for _, hi := range []*hostInfo{
		{NodeType: "ARBITER", IsArbiter: true, Version: "7.0.45-24"},
		{NodeType: "mongos", Version: "7.0.45-24"},
	} {
		g := &gaps{}
		fillFCV(context.Background(), nil, hi, newBudget(time.Minute), g)
		assert.Nil(t, hi.FCV, hi.NodeType)
		assert.Empty(t, g.list, hi.NodeType)
	}

	client, _ := unreachableClient(t, closedAddr(t), 100*time.Millisecond)
	g := &gaps{}
	hi := &hostInfo{NodeType: "replset", Version: "7.0.45-24"}

	start := time.Now()
	fillFCV(context.Background(), client, hi, newBudget(time.Minute), g)
	assert.Less(t, time.Since(start), 3*time.Second)
	assert.Nil(t, hi.FCV)
	require.Len(t, g.list, 1)
	assert.Equal(t, "This host", g.list[0].Section)
	assert.Equal(t, "FCV", g.list[0].Item)
}

func TestGetHostInfoIsMasterFailed(t *testing.T) {
	snap := &snapshot{
		IsMasterErr:     errors.New("server selection error: server selection timeout, current topology: { Type: Single }"),
		HostInfoErr:     context.DeadlineExceeded,
		CmdLineOptsErr:  context.DeadlineExceeded,
		ServerStatusErr: context.DeadlineExceeded,
	}

	hi, err := getHostInfo(context.Background(), nil, snap)
	assert.Nil(t, hi)
	require.Error(t, err)
	assert.Equal(t, "GetHostInfo.hostInfo: server selection error: server selection timeout, current topology: { Type: Single }",
		err.Error())
}

func TestGetHostInfoUnreachable(t *testing.T) {
	client, _ := unreachableClient(t, closedAddr(t), 200*time.Millisecond)

	ctx, cancel := newBudget(time.Hour).ctx(context.Background(), snapshotCallTimeout)
	defer cancel()

	snap := takeSnapshot(ctx, client)
	hi, err := getHostInfo(ctx, client, snap)
	assert.Nil(t, hi)
	require.Error(t, err)
	assert.True(t, strings.HasPrefix(err.Error(), "GetHostInfo.hostInfo: server selection error: server selection timeout"),
		err.Error())
}
