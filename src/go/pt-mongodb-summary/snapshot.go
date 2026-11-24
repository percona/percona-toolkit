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
	"time"

	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

type snapshot struct {
	IsMaster        proto.MasterDoc
	IsMasterRaw     bson.Raw
	IsMasterErr     error
	HostInfo        bson.Raw
	HostInfoErr     error
	CmdLineOpts     bson.Raw
	CmdLineOptsErr  error
	ServerStatus    bson.Raw
	ServerStatusErr error
}

func takeSnapshot(ctx context.Context, client *mongo.Client) *snapshot {
	s := &snapshot{}

	s.IsMasterRaw, s.IsMasterErr = snapshotCall(ctx, client, "isMaster")
	if s.IsMasterErr == nil {
		s.IsMasterErr = bson.Unmarshal(s.IsMasterRaw, &s.IsMaster)
	}

	s.HostInfo, s.HostInfoErr = snapshotCall(ctx, client, "hostInfo")
	s.CmdLineOpts, s.CmdLineOptsErr = snapshotCall(ctx, client, "getCmdLineOpts")
	s.ServerStatus, s.ServerStatusErr = snapshotCall(ctx, client, "serverStatus")

	return s
}

func snapshotCall(ctx context.Context, client *mongo.Client, cmd string) (bson.Raw, error) {
	raw, err := runRaw(ctx, client, "admin", bson.D{{Key: cmd, Value: 1}})
	if err != nil {
		log.Debugf("run('%s') error: %s", cmd, err)
	}

	return raw, err
}

func (s *snapshot) parsed() bson.Raw {
	parsed, _ := rawDoc(s.CmdLineOpts, "parsed")

	return parsed
}

func (s *snapshot) argv() []string {
	argv, _ := rawStrings(s.CmdLineOpts, "argv")

	return argv
}

func (s *snapshot) clusterRole() string {
	role, _ := rawString(s.CmdLineOpts, "parsed", "sharding", "clusterRole")

	return role
}

func (s *snapshot) isMongos() bool {
	return s.IsMaster.Msg == "isdbgrid"
}

func (s *snapshot) maxConns() (int64, bool) {
	current, ok := rawInt64(s.ServerStatus, "connections", "current")
	if !ok {
		return 0, false
	}

	available, ok := rawInt64(s.ServerStatus, "connections", "available")
	if !ok {
		return 0, false
	}

	queued, _ := rawInt64(s.ServerStatus, "connections", "queuedForEstablishment")

	return current + available + queued, true
}

func (s *snapshot) serverNow() (time.Time, bool) {
	return rawTime(s.ServerStatus, "localTime")
}
