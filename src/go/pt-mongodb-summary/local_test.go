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
	"errors"
	"fmt"
	"io/fs"
	"os"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/shirou/gopsutil/process"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
)

type fakeProcFS struct {
	files    map[string]string
	hostname string
	hostErr  error
}

func (f fakeProcFS) ReadFile(path string) ([]byte, error) {
	data, ok := f.files[path]
	if !ok {
		return nil, fs.ErrNotExist
	}

	return []byte(data), nil
}

func (f fakeProcFS) Hostname() (string, error) {
	return f.hostname, f.hostErr
}

func statLine(pid int64, comm string, startTicks int64) string {
	return fmt.Sprintf("%d (%s) S 1 %d %d 0 -1 4194560 100 0 0 0 10 5 0 0 20 0 30 0 %d 1000000 5000 "+
		"18446744073709551615 1 1 0 0 0 0 0 0 0 0 0 0 17 3 0 0 0 0 0\n", pid, comm, pid, pid, startTicks)
}

func cmdline(argv ...string) string {
	return strings.Join(argv, "\x00") + "\x00"
}

func localSnapshot(t *testing.T, pid, uptimeMillis int64, argv []string, hostname string) *snapshot {
	t.Helper()

	s := &snapshot{
		ServerStatus: mustRaw(t, bson.D{
			{Key: "host", Value: "db1:27017"},
			{Key: "pid", Value: pid},
			{Key: "uptime", Value: float64(uptimeMillis / 1000)},
			{Key: "uptimeMillis", Value: uptimeMillis},
			{Key: "localTime", Value: time.Now()},
		}),
		CmdLineOpts: mustRaw(t, bson.D{{Key: "argv", Value: argv}, {Key: "parsed", Value: bson.D{}}}),
	}
	if hostname != "" {
		s.HostInfo = mustRaw(t, bson.D{{Key: "system", Value: bson.D{{Key: "hostname", Value: hostname}}}})
	}

	return s
}

func TestDetectLocal(t *testing.T) {
	argv := []string{"mongod", "--replSet", "rs", "--port", "27017"}
	redacted := []string{"mongod", "--kmipClientCertificatePassword", "<password>", "--ldapQueryPassword=<password>"}
	secret := []string{"mongod", "--kmipClientCertificatePassword", "s3cr3t", "--ldapQueryPassword=x"}

	const uptimeMillis = 3600 * 1000

	startTicks := int64((10000 - 3600 - 3) * clockTicks)
	files := func(local []string, ticks int64) map[string]string {
		return map[string]string{
			"/proc/uptime":       "10000.00 50000.00\n",
			"/proc/4242/cmdline": cmdline(local...),
			"/proc/4242/stat":    statLine(4242, "mongod", ticks),
		}
	}
	without := func(m map[string]string, path string) map[string]string {
		delete(m, path)

		return m
	}
	with := func(m map[string]string, path, data string) map[string]string {
		m[path] = data

		return m
	}

	tests := []struct {
		name     string
		snap     *snapshot
		fs       fakeProcFS
		reason   string
		wantPid  int32
		wantDone bool
	}{
		{
			name:     "local",
			snap:     localSnapshot(t, 4242, uptimeMillis, argv, "db1:27017"),
			fs:       fakeProcFS{files: files(argv, startTicks), hostname: "db1"},
			wantPid:  4242,
			wantDone: true,
		},
		{
			name:     "hostname compared without port and case",
			snap:     localSnapshot(t, 4242, uptimeMillis, argv, "DB1.example.com:27017"),
			fs:       fakeProcFS{files: files(argv, startTicks), hostname: "db1.example.com"},
			wantPid:  4242,
			wantDone: true,
		},
		{
			name:     "redacted argv elements match any local value",
			snap:     localSnapshot(t, 4242, uptimeMillis, redacted, "db1"),
			fs:       fakeProcFS{files: files(secret, startTicks), hostname: "db1"},
			wantPid:  4242,
			wantDone: true,
		},
		{
			name:     "hostInfo not readable falls back to the serverStatus host",
			snap:     localSnapshot(t, 4242, uptimeMillis, argv, ""),
			fs:       fakeProcFS{files: files(argv, startTicks), hostname: "db1"},
			wantPid:  4242,
			wantDone: true,
		},
		{
			name:   "serverStatus host differs",
			snap:   localSnapshot(t, 4242, uptimeMillis, argv, ""),
			fs:     fakeProcFS{files: files(argv, startTicks), hostname: "elsewhere"},
			reason: "not the same host",
		},
		{
			name: "no hostname reported skips the hostname check",
			snap: &snapshot{
				ServerStatus: mustRaw(t, bson.D{
					{Key: "pid", Value: int64(4242)}, {Key: "uptimeMillis", Value: int64(uptimeMillis)},
				}),
				CmdLineOpts: mustRaw(t, bson.D{{Key: "argv", Value: argv}}),
			},
			fs:       fakeProcFS{files: files(argv, startTicks), hostname: "elsewhere"},
			wantPid:  4242,
			wantDone: true,
		},
		{
			name:     "local hostname unknown skips the hostname check",
			snap:     localSnapshot(t, 4242, uptimeMillis, argv, "db1:27017"),
			fs:       fakeProcFS{files: files(argv, startTicks), hostErr: errors.New("no hostname")},
			wantPid:  4242,
			wantDone: true,
		},
		{
			name:     "comm with spaces and parentheses",
			snap:     localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:       fakeProcFS{files: with(files(argv, 0), "/proc/4242/stat", statLine(4242, "mon (go) d", startTicks)), hostname: "db1"},
			wantPid:  4242,
			wantDone: true,
		},
		{
			name:   "hostname differs",
			snap:   localSnapshot(t, 4242, uptimeMillis, argv, "db2:27017"),
			fs:     fakeProcFS{files: files(argv, startTicks), hostname: "db1"},
			reason: "not the same host",
		},
		{
			name:   "hostname differs wins over a missing /proc",
			snap:   localSnapshot(t, 4242, uptimeMillis, argv, "db2:27017"),
			fs:     fakeProcFS{hostname: "db1"},
			reason: "not the same host",
		},
		{
			name:   "no /proc",
			snap:   localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:     fakeProcFS{hostname: "db1"},
			reason: "no /proc on this OS",
		},
		{
			name:    "cmdline unreadable",
			snap:    localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:      fakeProcFS{files: without(files(argv, startTicks), "/proc/4242/cmdline"), hostname: "db1"},
			reason:  "process not visible (hidepid, other PID namespace or user)",
			wantPid: 4242,
		},
		{
			name:    "cmdline empty",
			snap:    localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:      fakeProcFS{files: with(files(argv, startTicks), "/proc/4242/cmdline", ""), hostname: "db1"},
			reason:  "process not visible (hidepid, other PID namespace or user)",
			wantPid: 4242,
		},
		{
			name:    "stat unreadable",
			snap:    localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:      fakeProcFS{files: without(files(argv, startTicks), "/proc/4242/stat"), hostname: "db1"},
			reason:  "process not visible (hidepid, other PID namespace or user)",
			wantPid: 4242,
		},
		{
			name:    "argv differs",
			snap:    localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:      fakeProcFS{files: files([]string{"mongod", "--replSet", "rs", "--port", "27018"}, startTicks), hostname: "db1"},
			reason:  "argv differs",
			wantPid: 4242,
		},
		{
			name:    "argv longer",
			snap:    localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:      fakeProcFS{files: files(append(append([]string{}, argv...), "--quiet"), startTicks), hostname: "db1"},
			reason:  "argv differs",
			wantPid: 4242,
		},
		{
			name:    "redacted option name still compared",
			snap:    localSnapshot(t, 4242, uptimeMillis, []string{"mongod", "--ldapQueryPassword=<password>"}, "db1"),
			fs:      fakeProcFS{files: files([]string{"mongod", "--other=x"}, startTicks), hostname: "db1"},
			reason:  "argv differs",
			wantPid: 4242,
		},
		{
			name:    "process start time off by 2 h",
			snap:    localSnapshot(t, 4242, uptimeMillis, argv, "db1"),
			fs:      fakeProcFS{files: files(argv, startTicks+2*3600*clockTicks), hostname: "db1"},
			reason:  "process start time differs",
			wantPid: 4242,
		},
		{
			name:   "serverStatus not readable",
			snap:   &snapshot{CmdLineOpts: mustRaw(t, bson.D{{Key: "argv", Value: argv}})},
			fs:     fakeProcFS{files: files(argv, startTicks), hostname: "db1"},
			reason: "serverStatus or getCmdLineOpts not readable",
		},
		{
			name: "getCmdLineOpts not readable",
			snap: &snapshot{ServerStatus: mustRaw(t, bson.D{
				{Key: "pid", Value: int64(4242)}, {Key: "uptimeMillis", Value: int64(uptimeMillis)},
			})},
			fs:     fakeProcFS{files: files(argv, startTicks), hostname: "db1"},
			reason: "serverStatus or getCmdLineOpts not readable",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lp := detectLocal(tt.snap, tt.fs)
			assert.Equal(t, tt.wantDone, lp.IsLocal)
			assert.Equal(t, tt.reason, lp.Reason)
			assert.Equal(t, tt.wantPid, lp.Pid)
			assert.Empty(t, lp.Exe)
			assert.Empty(t, lp.User)
			assert.Zero(t, lp.MongodCount)
		})
	}
}

func TestDetectLocalUptimeSeconds(t *testing.T) {
	argv := []string{"mongod"}
	snap := &snapshot{
		ServerStatus: mustRaw(t, bson.D{{Key: "pid", Value: int32(7)}, {Key: "uptime", Value: int32(100)}}),
		CmdLineOpts:  mustRaw(t, bson.D{{Key: "argv", Value: argv}}),
	}
	fs := fakeProcFS{files: map[string]string{
		"/proc/uptime":    "1000.50 1.00\n",
		"/proc/7/cmdline": cmdline(argv...),
		"/proc/7/stat":    statLine(7, "mongod", 90000),
	}}

	lp := detectLocal(snap, fs)
	assert.True(t, lp.IsLocal, lp.Reason)
	assert.Equal(t, int32(7), lp.Pid)
}

func TestDetectLocalSelf(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("needs /proc")
	}

	pid := int32(os.Getpid())
	p, err := process.NewProcess(pid)
	require.NoError(t, err)
	created, err := p.CreateTime()
	require.NoError(t, err)

	hostname, err := os.Hostname()
	require.NoError(t, err)

	snap := localSnapshot(t, int64(pid), time.Now().UnixMilli()-created, os.Args, hostname+":27017")

	lp := detectLocal(snap, systemProcFS{})
	require.True(t, lp.IsLocal, lp.Reason)
	assert.Equal(t, pid, lp.Pid)

	lp = withProcessDetails(lp)
	assert.NotEmpty(t, lp.Exe)
	assert.NotEmpty(t, lp.User)
	assert.GreaterOrEqual(t, lp.MongodCount, 0)

	snap = localSnapshot(t, int64(pid), time.Now().UnixMilli()-created+3600*1000, os.Args, hostname)
	assert.Equal(t, "process start time differs", detectLocal(snap, systemProcFS{}).Reason)
}

func TestWithProcessDetailsNotLocal(t *testing.T) {
	lp := withProcessDetails(localProcess{Pid: int32(os.Getpid()), Reason: "argv differs"})
	assert.Equal(t, localProcess{Pid: int32(os.Getpid()), Reason: "argv differs"}, lp)
}
