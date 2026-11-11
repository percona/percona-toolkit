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
	"os/exec"
	"path/filepath"
	"regexp"
	"testing"
	"time"

	"context"
	"os"

	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	log "github.com/sirupsen/logrus"
	"github.com/stretchr/testify/require"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

const (
	TOOL_PATH = "../../../bin/pt-mongodb-summary"
)

// semVerRE is the SemVer pattern from https://semver.org (RE2-compatible
// variant), used to validate the version line printed by --version.
const semVerRE = `(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)` +
	`(?:-(?:(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?` +
	`(?:\+(?:[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?`

func TestVersionOption(t *testing.T) {
	out, err := exec.Command(TOOL_PATH, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(toolname + `\n.*Version v?` + semVerRE + `\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", toolname, out)
	}
}

func TestGetHostInfo(t *testing.T) {
	testCases := []struct {
		name string
		port string
		want []string
	}{
		{
			name: "from_mongos",
			port: tu.MongoDBMongosPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17004", "127.0.0.1:17005", "127.0.0.1:17007"},
		},
		{
			name: "from_mongod",
			port: tu.MongoDBShard1PrimaryPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17003"},
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			client, err := tu.TestClient(ctx, test.port)
			if err != nil {
				t.Fatalf("cannot get a new MongoDB client: %s", err)
			}

			_, err = getHostInfo(ctx, client, takeSnapshot(ctx, client))
			if err != nil {
				t.Errorf("getHostnames: %v", err)
			}
		})
	}
}

func TestGetHostInfoResult(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := tu.TestClient(ctx, tu.MongoDBShard1PrimaryPort)
	require.NoError(t, err, "cannot get a new MongoDB client")

	host, err := getHostInfo(ctx, client, takeSnapshot(ctx, client))
	require.NoError(t, err, "getHostInfo error")
	require.NotEmpty(t, host)
}

func TestClusterWideInfo(t *testing.T) {
	testCases := []struct {
		name string
		port string
		want []string
	}{
		{
			name: "from_mongos",
			port: tu.MongoDBMongosPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17004", "127.0.0.1:17005", "127.0.0.1:17007"},
		},
		{
			name: "from_mongod",
			port: tu.MongoDBShard1PrimaryPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17003"},
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			client, err := tu.TestClient(ctx, test.port)
			if err != nil {
				t.Fatalf("cannot get a new MongoDB client: %s", err)
			}

			_, err = getClusterwideInfo(ctx, client)
			if err != nil {
				t.Errorf("getClisterWideInfo error: %v", err)
			}
		})
	}
}

func TestClusterWideNotAuthorized(t *testing.T) {
	preimages := bson.D{{Key: "name", Value: "system.preimages"}, {Key: "type", Value: "collection"}}
	addr := noLoginServer(t, func(string) bson.D {
		return bson.D{{Key: "ismaster", Value: true}, {Key: "msg", Value: "isdbgrid"}}
	}, map[string]bson.D{
		"listDatabases": {
			{Key: "databases", Value: bson.A{bson.D{{Key: "name", Value: "config"}}}},
			{Key: "ok", Value: 1.0},
		},
		"listCollections": {
			{Key: "cursor", Value: bson.D{
				{Key: "id", Value: int64(0)},
				{Key: "ns", Value: "config.$cmd.listCollections"},
				{Key: "firstBatch", Value: bson.A{preimages}},
			}},
			{Key: "ok", Value: 1.0},
		},
		"collStats": {
			{Key: "ok", Value: 0.0}, {Key: "code", Value: int32(13)}, {Key: "codeName", Value: "Unauthorized"},
			{Key: "errmsg", Value: `not authorized on config to execute command { collStats: "system.preimages" }`},
		},
	})
	client, co := fakeClient(t, addr)
	snap := takeSnapshot(context.Background(), client)
	require.True(t, snap.isMongos())

	hi := &hostInfo{NodeType: typeMongos}
	ci := collect(context.Background(), client, co, &cliOptions{}, newBudget(time.Minute), snap, hi)
	assert.Nil(t, ci.ClusterWideInfo)
	assert.Contains(t, ci.Errors, collectError{
		Section: "Cluster wide", Item: "Cluster wide", Code: 13,
		Reason: "not authorized (needs collStats on config system collections)",
	})
}

func TestAfterApply(t *testing.T) {
	level := log.GetLevel()
	t.Cleanup(func() { log.SetLevel(level) })

	tests := []struct {
		name     string
		input    *cliOptions
		wantErr  bool
		wantHost string
		wantPort string
	}{
		{name: "Defaults, no positional arg", input: &cliOptions{LogLevel: "warn"}},
		{name: "Positional host:port", input: &cliOptions{LogLevel: "warn", HostPort: "test.example.com:27019"}, wantHost: "test.example.com", wantPort: "27019"},
		{name: "Positional host without port", input: &cliOptions{LogLevel: "warn", HostPort: "myhost"}, wantHost: "myhost"},
		{name: "Version skips the rest", input: &cliOptions{Version: true, LogLevel: "bogus"}},
		{name: "Error: invalid log level", input: &cliOptions{LogLevel: "bogus"}, wantErr: true},
		{name: "Error: URI and Host together", input: &cliOptions{LogLevel: "warn", URI: "mongodb://test", Host: "localhost"}, wantErr: true},
		{name: "Error: positional arg and Host flag together", input: &cliOptions{LogLevel: "warn", Host: "newhost", HostPort: "legacy:27017"}, wantErr: true},
		{name: "Error: positional arg and URI together", input: &cliOptions{LogLevel: "warn", URI: "mongodb://test", HostPort: "legacy:27017"}, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.input.AfterApply()
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.wantHost, tt.input.Host)
			assert.Equal(t, tt.wantPort, tt.input.Port)
			assert.Empty(t, tt.input.HostPort)
		})
	}
}

func TestSetupFlags(t *testing.T) {
	oldArgs, level := os.Args, log.GetLevel()
	t.Cleanup(func() {
		os.Args = oldArgs
		log.SetLevel(level)
	})

	tests := []struct {
		name string
		args []string
		want cliOptions
	}{
		{
			name: "Defaults",
			args: []string{},
			want: cliOptions{
				VersionCheckFlag: config.VersionCheckFlag{VersionCheck: true},
				LogLevel:         "warn", OutputFormat: "text", RunningOpsSamples: 5, RunningOpsInterval: 1000,
			},
		},
		{
			name: "Short flags and positional host",
			args: []string{"-c", "-u", "cm", "-p", "secret", "-a", "mydb", "-l", "info", "-f", "json", "-s", "0", "-i", "500", "h1:1234"},
			want: cliOptions{
				VersionCheckFlag: config.VersionCheckFlag{VersionCheck: true}, SkipVersionCheck: true,
				User: "cm", Password: config.StdinRequestString("secret"), AuthDB: "mydb",
				LogLevel: "info", OutputFormat: "json", RunningOpsSamples: 0, RunningOpsInterval: 500, Host: "h1", Port: "1234",
			},
		},
		{
			name: "Long flags",
			args: []string{"--no-version-check", "--uri", "mongodb://h2:27019", "--username=cm", "--password=secret"},
			want: cliOptions{
				URI: "mongodb://h2:27019", User: "cm", Password: config.StdinRequestString("secret"),
				LogLevel: "warn", OutputFormat: "text", RunningOpsSamples: 5, RunningOpsInterval: 1000,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			os.Args = append([]string{toolname, "--config", ""}, tt.args...)
			got := &cliOptions{}
			_, _, err := config.Setup(toolname, got)
			require.NoError(t, err)
			got.Config = nil
			assert.Equal(t, tt.want, *got)
		})
	}

	t.Run("Config file", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "pt-mongodb-summary.conf")
		require.NoError(t, os.WriteFile(path, []byte("username=cm\nno-version-check\nrunning-ops-samples=2\n"), 0o600))
		os.Args = []string{toolname, "--config", path, "h3:27020"}
		got := &cliOptions{}
		_, _, err := config.Setup(toolname, got)
		require.NoError(t, err)
		assert.False(t, got.VersionCheck)
		assert.Equal(t, "cm", got.User)
		assert.Equal(t, 2, got.RunningOpsSamples)
		assert.Equal(t, "h3", got.Host)
		assert.Equal(t, "27020", got.Port)
	})
}

func TestGetClientOptions(t *testing.T) {
	tests := []struct {
		name     string
		opts     *cliOptions
		wantErr  bool
		validate func(*testing.T, *options.ClientOptions)
	}{
		{
			name: "Default values when everything is empty",
			opts: &cliOptions{},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, []string{"localhost:27017"}, co.Hosts)
				assert.Nil(t, co.Auth)
			},
		},
		{
			name: "Priority to URI",
			opts: &cliOptions{
				URI: "mongodb://remote-host:28000",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, []string{"remote-host:28000"}, co.Hosts)
			},
		},
		{
			name: "Flags override Auth in URI",
			opts: &cliOptions{
				URI:      "mongodb://old-user:old-pass@localhost:27017",
				User:     "new-user",
				Password: config.StdinRequestString("new-password"),
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "new-user", co.Auth.Username)
				assert.Equal(t, "new-password", co.Auth.Password)
			},
		},
		{
			name: "Only host and port flags",
			opts: &cliOptions{
				Host: "127.0.0.1",
				Port: "27019",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, []string{"127.0.0.1:27019"}, co.Hosts)
			},
		},
		{
			name: "Invalid URI should return error",
			opts: &cliOptions{
				URI: "not-a-valid-uri",
			},
			wantErr: true,
		},
		{
			name: "Explicit AuthDB wins over the URI credentials' source",
			opts: &cliOptions{
				URI:    "mongodb://u:p@localhost:27017/?authSource=other",
				AuthDB: "monitoring",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "monitoring", co.Auth.AuthSource)
			},
		},
		{
			name: "URI authSource used for flag credentials",
			opts: &cliOptions{
				URI:  "mongodb://localhost:27017/?authSource=custom",
				User: "mon",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "custom", co.Auth.AuthSource)
			},
		},
		{
			name: "URI database used for flag credentials",
			opts: &cliOptions{
				URI:  "mongodb://localhost:27017/mydb",
				User: "mon",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "mydb", co.Auth.AuthSource)
			},
		},
		{
			name: "Username only leaves the driver default",
			opts: &cliOptions{User: "mon"},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "", co.Auth.AuthSource)
			},
		},
		{
			name: "AuthDB without a user sets no credential",
			opts: &cliOptions{AuthDB: "mydb"},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Nil(t, co.Auth)
			},
		},
		{
			name: "External mechanism keeps $external",
			opts: &cliOptions{
				URI:    "mongodb://user@localhost:27017/?authMechanism=GSSAPI",
				AuthDB: "admin",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "$external", co.Auth.AuthSource)
			},
		},
		{
			name: "AuthDB flag used when the URI has no authSource",
			opts: &cliOptions{
				User:   "user",
				AuthDB: "mydb",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "mydb", co.Auth.AuthSource)
			},
		},
		{
			name: "AuthDB via URI (check if preserved)",
			opts: &cliOptions{
				URI: "mongodb://user@localhost:27017/admin?authSource=custom_db",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "user", co.Auth.Username)
				assert.Equal(t, "custom_db", co.Auth.AuthSource)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := getClientOptions(tt.opts)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			assert.NoError(t, err)
			assert.NotNil(t, got)

			if tt.validate != nil {
				tt.validate(t, got)
			}

			assert.NotNil(t, got.ServerSelectionTimeout)
			assert.True(t, *got.Direct)
		})
	}
}

func TestGetMongosInfo(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := tu.TestClient(ctx, tu.MongoDBMongosPort)
	require.NoError(t, err)

	g := &gaps{}
	info, shards := getShardingInfo(ctx, client, takeSnapshot(ctx, client), &hostInfo{NodeType: typeMongos},
		newBudget(time.Minute), g)
	require.Empty(t, g.list)
	require.NotNil(t, info)
	require.NotEmpty(t, info.Instances)
	require.NotNil(t, shards)
	require.NotEmpty(t, shards.Shards)

	for _, m := range info.Instances {
		require.NotEmpty(t, m.Name)
		require.NotEmpty(t, m.Version)
		require.NotEqual(t, 0, m.UpTime)
		require.False(t, m.LastPing.IsZero())
	}
}

func TestNewArbiterHostInfo(t *testing.T) {
	hi := newArbiterHostInfo(proto.MasterDoc{SetName: "rs0", Me: "arb:27017", ArbiterOnly: true})
	assert.Equal(t, &hostInfo{
		Hostname:       "arb:27017",
		ReplicasetName: "rs0",
		NodeType:       "ARBITER",
		IsArbiter:      true,
	}, hi)

	hi = newArbiterHostInfo(proto.MasterDoc{Me: "arb:27017", ArbiterOnly: true})
	assert.Empty(t, hi.ReplicasetName)
}

func TestFormatResultsArbiter(t *testing.T) {
	resident := int64(64)
	ci := &collectedInfo{
		HostInfo: &hostInfo{
			Hostname:       "arb:27017",
			ReplicasetName: "rs0",
			NodeType:       "ARBITER",
			IsArbiter:      true,
		},
		StartupOptions:   &startupOptions{Options: []configOption{{Name: "net.port", Value: "27017"}}},
		Memory:           &memoryInfo{ResidentMB: &resident},
		Connections:      &connectionsInfo{Current: 3, Available: 816, Limit: 819},
		SecuritySettings: &security{Auth: "enabled", SSL: "disabled", Port: 27017, IsArbiter: true},
	}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)

	for _, want := range []string{
		"Process Type | ARBITER", "# Arbiter", "Auth   : enabled",
		"This node is a replica-set ARBITER: it holds no data and does not accept user logins,\n" +
			"so host facts, startup warnings, user/role counts, FCV, profiler settings, database inventory,\n" +
			"mongos and oplog details are not collected from it.\n",
		"# Startup Options", "net.port = 27017", "# Memory", "Resident Set (RSS) | 64.00 MB",
		"# Connections & Profiling", "Limit | 819 (current + available)",
	} {
		assert.Contains(t, string(out), want)
	}
	for _, unwanted := range []string{
		"# Mongos", "# Instances", "PID Owner", "Version |", "Built On", "FCV |",
		"# Command line arguments", "# Running Ops", "Users  :", "Roles  :", "Slow Op Threshold",
		"# OS & Production Checks", "# Change Streams", "# Database Inventory", "# Not collected",
	} {
		assert.NotContains(t, string(out), unwanted)
	}
	assert.Equal(t, []string{
		"This host", "Report On arb:27017", "Arbiter", "Startup Options", "Memory", "Connections & Profiling", "Security",
	}, headerTitles(string(out)))
}

func TestFormatResultsDataNode(t *testing.T) {
	expire := int64(0)
	ci := &collectedInfo{
		ReplicaMembers: []proto.Members{
			{ID: 4242, Name: "m1:27017", StateStr: "PRIMARY", Set: "rs0"},
			{Name: "m2:27017", StateStr: "SECONDARY", Set: "rs0"},
		},
		HostInfo: &hostInfo{
			Hostname:          "m1",
			HostOsType:        "Linux",
			HostSystemCPUArch: "x86_64",
			ProcessName:       "mongod",
			Version:           "7.0.37",
			FCV:               &fcvInfo{Version: "6.0"},
			ProcCreateTime:    time.Date(2026, 10, 27, 18, 11, 40, 0, time.FixedZone("CEST", 2*3600)),
			ReplicasetName:    "rs0",
			NodeType:          "replset",
			CmdlineArgs:       []string{"mongod", "--replSet", "rs0"},
		},
		OSChecks:         &osChecks{OSName: "Ubuntu", MaxOpenFiles: 64000, LocalSkipReason: "argv differs"},
		StartupOptions:   &startupOptions{Options: []configOption{{Name: "replication.replSet", Value: "rs0"}}},
		Connections:      &connectionsInfo{Current: 5, Available: 95, Limit: 100},
		Profiling:        &profilingInfo{SlowMs: 100, SampleRate: 1},
		SecuritySettings: &security{Users: 1, Auth: "enabled", SSL: "disabled", Port: 27017, CountsReadable: true},
		ChangeStreams:    &changeStreamsInfo{PreAndPostImagesExpire: "off", Readable: true, PreImageDocs: &expire},
		Errors: []collectError{
			{Section: "This host", Item: "Host facts", Code: 13, Reason: "not authorized (needs hostInfo: clusterMonitor)"},
		},
	}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)

	for _, want := range []string{
		"# Instances", "  4242 m1:27017 ", "\n       m2:27017 ", "PID Owner | mongod", "Version | 7.0.37",
		"FCV | 6.0 (binary is 7.0)", "Built On | Linux x86_64", "Started | 2026-10-27 16:11:40 UTC",
		"Process Type | replset", "# Command line arguments", "Users  : 1", "Roles  : 0",
		"Open files limit | 64000\n", "Local checks | skipped: argv differs", "replication.replSet = rs0",
		"Limit | 100 (current + available)", "Slow Op Threshold | 100 ms\n",
		"Pre/Post Images Expire | off (kept until the matching oplog entry is removed)",
		"Host facts | not authorized (needs hostInfo: clusterMonitor)",
	} {
		assert.Contains(t, string(out), want)
	}
	assert.NotContains(t, string(out), "# Arbiter")
	assert.NotContains(t, string(out), "not readable")
	assert.NotContains(t, string(out), "     0 m2:27017")
	assert.Equal(t, []string{
		"Instances", "This host", "Report On m1", "OS & Production Checks", "Command line arguments",
		"Startup Options", "Connections & Profiling", "Security", "Change Streams", "Not collected",
	}, headerTitles(string(out)))
}

func TestRunStage(t *testing.T) {
	g := &gaps{}
	ran := false
	runStage(newBudget(time.Hour), g, "security", true, func() { ran = true },
		collectError{Section: "Security", Item: "Security"})
	assert.True(t, ran)
	assert.Empty(t, g.list)

	ran = false
	runStage(newBudget(time.Hour), g, "fcv", false, func() { ran = true },
		collectError{Section: "This host", Item: "FCV"})
	assert.False(t, ran)
	assert.Empty(t, g.list)

	expired := &budget{deadline: time.Now().Add(-time.Second)}
	runStage(expired, g, "fcv", false, func() { ran = true },
		collectError{Section: "This host", Item: "FCV"})
	assert.False(t, ran)
	assert.Empty(t, g.list)

	runStage(expired, g, "member phase", true, func() { ran = true },
		collectError{Section: "Instances", Item: "Instances"},
		collectError{Section: "Oplog", Item: "Oplog"})
	assert.False(t, ran)
	assert.Equal(t, []collectError{
		{Section: "Instances", Item: "Instances", Reason: "timed out"},
		{Section: "Oplog", Item: "Oplog", Reason: "timed out"},
	}, g.list)
}

func TestRunStageRemoteArbiter(t *testing.T) {
	client, co, snap, _ := remoteArbiterLab(t)

	opts := &cliOptions{RunningOpsSamples: DefaultRunningOpsSamples, RunningOpsInterval: DefaultRunningOpsInterval}
	note := collectError{
		Section: "Arbiter",
		Item:    "Arbiter",
		Reason:  "accepts no logins; for full details run the tool on its host against localhost",
	}

	ci := collect(context.Background(), client, co, opts, newBudget(time.Minute), snap, newArbiterHostInfo(snap.IsMaster))
	assert.Equal(t, []collectError{note}, ci.Errors)

	assert.Nil(t, ci.RunningOps)
	assert.Nil(t, ci.OSChecks)
	assert.Nil(t, ci.StartupOptions)
	assert.Nil(t, ci.WiredTiger)
	assert.Nil(t, ci.Memory)
	assert.Nil(t, ci.Connections)
	assert.Nil(t, ci.Profiling)
	assert.Nil(t, ci.SecuritySettings)
	assert.Nil(t, ci.ChangeStreams)
	assert.Nil(t, ci.DatabaseInventory)
	assert.Nil(t, ci.MongosInfo)
	assert.Nil(t, ci.ShardsInfo)
	assert.Nil(t, ci.ClusterWideInfo)
	assert.Nil(t, ci.BalancerStats)

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	assert.Equal(t, "\n"+header("Not collected")+"\n"+fmt.Sprintf("%25s | %s\n", note.Item, note.Reason),
		sectionBetweenHeaders(string(out), "Not collected"))

	expired := &budget{deadline: time.Now().Add(-time.Second)}
	ci = collect(context.Background(), nil, nil, opts, expired, snap, newArbiterHostInfo(snap.IsMaster))
	assert.Equal(t, []collectError{
		note,
		{Section: "Instances", Item: "Instances", Reason: "timed out"},
		{Section: "Oplog", Item: "Oplog", Reason: "timed out"},
	}, ci.Errors)
}
