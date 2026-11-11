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
	"strings"
	"time"

	"github.com/pkg/errors"
	"github.com/shirou/gopsutil/process"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

const codeUnknownFCV = 258

var errNotAuthenticated = errors.New("authentication required: pass --username/--password (and --authenticationDatabase)")

type hostInfo struct {
	Hostname          string
	HostOsType        string
	HostSystemCPUArch string
	HostDatabases     int
	HostCollections   int
	DBPath            string

	ProcPath         string
	ProcUserName     string
	ProcCreateTime   time.Time
	ProcProcessCount int

	CmdlineArgs    []string
	ProcessName    string
	ReplicasetName string
	Version        string
	NodeType       string
	IsArbiter      bool

	FCV             *fcvInfo
	IsLocal         bool
	LocalSkipReason string
	ClusterRole     string
}

type fcvInfo struct {
	Version         string `bson:"version"`
	TargetVersion   string `bson:"targetVersion"`
	PreviousVersion string `bson:"previousVersion"`
}

func (h *hostInfo) FCVSummary() string {
	return describeFCV(h.FCV, h.Version)
}

func newArbiterHostInfo(md proto.MasterDoc) *hostInfo {
	setName, _ := md.SetName.(string)

	return &hostInfo{
		NodeType:       "ARBITER",
		Hostname:       md.Me,
		ReplicasetName: setName,
		IsArbiter:      true,
	}
}

func getHostInfo(ctx context.Context, client *mongo.Client, snap *snapshot) (*hostInfo, error) {
	if snap.IsMasterErr != nil {
		return nil, errors.Wrap(snap.IsMasterErr, "GetHostInfo.hostInfo")
	}

	if !snap.IsMaster.IsArbiter() && requiresAuth(snap.HostInfoErr) && requiresAuth(snap.CmdLineOptsErr) &&
		requiresAuth(snap.ServerStatusErr) {
		return nil, errNotAuthenticated
	}

	var buildInfo bson.Raw
	if snap.ServerStatusErr != nil && client != nil {
		var err error
		if buildInfo, err = runRaw(ctx, client, "admin", bson.D{{Key: "buildInfo", Value: 1}}); err != nil {
			log.Debugf("run('buildInfo') error: %s", err)
		}
	}

	return newHostInfo(snap, buildInfo, withProcessDetails(detectLocal(snap, systemProcFS{}))), nil
}

func newHostInfo(snap *snapshot, buildInfo bson.Raw, lp localProcess) *hostInfo {
	md := snap.IsMaster

	var hi *hostInfo
	if md.IsArbiter() {
		hi = newArbiterHostInfo(md)
	} else {
		setName, _ := md.SetName.(string)
		hi = &hostInfo{Hostname: md.Me, ReplicasetName: setName, NodeType: getNodeType(md)}
	}

	if name, _ := rawString(snap.HostInfo, "system", "hostname"); name != "" {
		hi.Hostname = name
	} else if hi.Hostname == "" {
		hi.Hostname, _ = rawString(snap.ServerStatus, "host")
	}

	hi.HostOsType, _ = rawString(snap.HostInfo, "os", "type")
	hi.HostSystemCPUArch, _ = rawString(snap.HostInfo, "system", "cpuArch")
	hi.DBPath, _ = rawString(snap.parsed(), "storage", "dbPath")
	hi.ClusterRole = snap.clusterRole()

	if argv := snap.argv(); len(argv) > 0 {
		hi.CmdlineArgs = argv
	}

	hi.ProcessName, _ = rawString(snap.ServerStatus, "process")
	if setName, _ := rawString(snap.ServerStatus, "repl", "setName"); setName != "" {
		hi.ReplicasetName = setName
	}

	if hi.Version, _ = rawString(snap.ServerStatus, "version"); hi.Version == "" {
		hi.Version, _ = rawString(buildInfo, "version")
	}

	hi.ProcCreateTime = serverStartTime(snap.ServerStatus)

	hi.IsLocal, hi.LocalSkipReason = lp.IsLocal, lp.Reason
	if lp.IsLocal {
		hi.ProcPath, hi.ProcUserName, hi.ProcProcessCount = lp.Exe, lp.User, lp.MongodCount
	}

	return hi
}

func requiresAuth(err error) bool {
	return err != nil && strings.Contains(err.Error(), "requires authentication")
}

func serverStartTime(ss bson.Raw) time.Time {
	now, ok := rawTime(ss, "localTime")
	if !ok {
		return time.Time{}
	}

	if ms, ok := rawInt64(ss, "uptimeMillis"); ok {
		return now.Add(-time.Duration(ms) * time.Millisecond).Truncate(time.Second)
	}

	if s, ok := rawFloat(ss, "uptime"); ok {
		return now.Add(-time.Duration(s * float64(time.Second))).Truncate(time.Second)
	}

	return time.Time{}
}

func fillFCV(ctx context.Context, client *mongo.Client, hi *hostInfo, b *budget, g *gaps) {
	if hi.IsArbiter || hi.NodeType == typeMongos {
		return
	}

	fctx, cancel := b.ctx(ctx, nodeCallTimeout)
	defer cancel()

	cmd := bson.D{{Key: "getParameter", Value: 1}, {Key: "featureCompatibilityVersion", Value: 1}}
	doc, err := runRaw(fctx, client, "admin", cmd)
	setFCV(hi, doc, err, g)
}

func setFCV(hi *hostInfo, doc bson.Raw, err error, g *gaps) {
	switch {
	case err == nil:
		hi.FCV = fcvFromReply(doc)
	case errorCode(err) == codeUnknownFCV || strings.Contains(err.Error(), "UnknownFeatureCompatibilityVersion"):
		log.Infof("cannot get FCV: %s", err)
	default:
		g.add("This host", "FCV", "getParameter: clusterMonitor", err)
	}
}

func fcvFromReply(doc bson.Raw) *fcvInfo {
	if v, ok := rawString(doc, "featureCompatibilityVersion"); ok && v != "" {
		return &fcvInfo{Version: v}
	}

	d, ok := rawDoc(doc, "featureCompatibilityVersion")
	if !ok {
		return nil
	}

	f := &fcvInfo{}
	f.Version, _ = rawString(d, "version")
	f.TargetVersion, _ = rawString(d, "targetVersion")
	f.PreviousVersion, _ = rawString(d, "previousVersion")

	if f.Version == "" {
		return nil
	}

	return f
}

func describeFCV(f *fcvInfo, binaryVersion string) string {
	if f == nil || f.Version == "" {
		return ""
	}

	binary := majorMinor(binaryVersion)

	switch {
	case f.PreviousVersion != "":
		return f.Version + " (downgrading from " + f.PreviousVersion + ")"
	case f.TargetVersion != "" && f.TargetVersion != f.Version:
		return f.Version + " (upgrading to " + f.TargetVersion + ")"
	case f.TargetVersion != "" && binary != "":
		return f.Version + " (downgrading from " + binary + ")"
	case f.TargetVersion != "":
		return f.Version + " (downgrading)"
	case binary != "" && binary != f.Version:
		return f.Version + " (binary is " + binary + ")"
	}

	return f.Version
}

func majorMinor(version string) string {
	parts := strings.SplitN(version, ".", 3)
	if len(parts) < 2 {
		return ""
	}

	major, minor := leadingDigits(parts[0]), leadingDigits(parts[1])
	if major == "" || minor == "" {
		return ""
	}

	return major + "." + minor
}

func leadingDigits(s string) string {
	end := 0
	for end < len(s) && s[end] >= '0' && s[end] <= '9' {
		end++
	}

	return s[:end]
}

func countMongodProcesses() (int, error) {
	pids, err := process.Pids()
	if err != nil {
		return 0, err
	}

	count := 0

	for _, pid := range pids {
		p, err := process.NewProcess(pid)
		if err != nil {
			continue
		}

		if name, _ := p.Name(); name == "mongod" || name == typeMongos {
			count++
		}
	}
	return count, nil
}

func getNodeType(md proto.MasterDoc) string {
	if md.SetName != nil || md.Hosts != nil {
		return "replset"
	} else if md.Msg == "isdbgrid" {
		return typeMongos
	}
	return "mongod"
}
