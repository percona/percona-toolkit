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
	"math"
	"net"
	"os"
	"strconv"
	"strings"

	"github.com/shirou/gopsutil/process"
	"go.mongodb.org/mongo-driver/bson"
)

const (
	clockTicks        = 100
	localAgeTolerance = 60

	reasonNotSameHost   = "not the same host"
	reasonNotVisible    = "process not visible (hidepid, other PID namespace or user)"
	reasonNoProc        = "no /proc on this OS"
	reasonArgvDiffers   = "argv differs"
	reasonStartDiffers  = "process start time differs"
	reasonServerProcess = "serverStatus or getCmdLineOpts not readable"
	redactedArgv        = "<password>"
)

type procFS interface {
	ReadFile(path string) ([]byte, error)
	Hostname() (string, error)
}

type systemProcFS struct{}

func (systemProcFS) ReadFile(path string) ([]byte, error) {
	return os.ReadFile(path)
}

func (systemProcFS) Hostname() (string, error) {
	return os.Hostname()
}

type localProcess struct {
	IsLocal     bool
	Reason      string
	Pid         int32
	Exe, User   string
	MongodCount int
}

func detectLocal(snap *snapshot, fs procFS) localProcess {
	reported, _ := rawString(snap.HostInfo, "system", "hostname")
	if reported == "" {
		reported, _ = rawString(snap.ServerStatus, "host")
	}

	if reported != "" {
		if local, err := fs.Hostname(); err == nil && !sameHost(local, reported) {
			return localProcess{Reason: reasonNotSameHost}
		}
	}

	bootUptime, ok := readUptime(fs)
	if !ok {
		return localProcess{Reason: reasonNoProc}
	}

	pid, okPid := rawInt64(snap.ServerStatus, "pid")
	uptime, okUptime := serverUptime(snap.ServerStatus)
	argv := snap.argv()
	if !okPid || !okUptime || len(argv) == 0 || pid <= 0 || pid > math.MaxInt32 {
		return localProcess{Reason: reasonServerProcess}
	}

	lp := localProcess{Pid: int32(pid)}

	cmdline, err := fs.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	if err != nil || len(cmdline) == 0 {
		lp.Reason = reasonNotVisible

		return lp
	}

	if !argvMatches(argv, strings.Split(strings.TrimSuffix(string(cmdline), "\x00"), "\x00")) {
		lp.Reason = reasonArgvDiffers

		return lp
	}

	stat, err := fs.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		lp.Reason = reasonNotVisible

		return lp
	}

	startTicks, ok := statStartTicks(stat)
	if !ok {
		lp.Reason = reasonNotVisible

		return lp
	}

	age := bootUptime - float64(startTicks)/clockTicks
	if math.Abs(age-uptime) > localAgeTolerance {
		lp.Reason = reasonStartDiffers

		return lp
	}

	lp.IsLocal = true

	return lp
}

func withProcessDetails(lp localProcess) localProcess {
	if !lp.IsLocal {
		return lp
	}

	if p, err := process.NewProcess(lp.Pid); err == nil {
		lp.Exe, _ = p.Exe()

		if name, err := p.Username(); err == nil {
			lp.User = name
		} else if uids, err := p.Uids(); err == nil && len(uids) > 0 {
			lp.User = strconv.Itoa(int(uids[0]))
		}
	}

	lp.MongodCount, _ = countMongodProcesses()

	return lp
}

func sameHost(local, reported string) bool {
	host, _, err := net.SplitHostPort(reported)
	if err != nil {
		host = reported
	}

	return strings.EqualFold(local, host)
}

func readUptime(fs procFS) (float64, bool) {
	data, err := fs.ReadFile("/proc/uptime")
	if err != nil {
		return 0, false
	}

	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0, false
	}

	up, err := strconv.ParseFloat(fields[0], 64)

	return up, err == nil
}

func serverUptime(ss bson.Raw) (float64, bool) {
	if ms, ok := rawInt64(ss, "uptimeMillis"); ok {
		return float64(ms) / 1000, true
	}

	return rawFloat(ss, "uptime")
}

func statStartTicks(stat []byte) (uint64, bool) {
	s := string(stat)

	end := strings.LastIndexByte(s, ')')
	if end < 0 {
		return 0, false
	}

	fields := strings.Fields(s[end+1:])
	if len(fields) < 20 {
		return 0, false
	}

	ticks, err := strconv.ParseUint(fields[19], 10, 64)

	return ticks, err == nil
}

func argvMatches(server, local []string) bool {
	if len(server) != len(local) {
		return false
	}

	for i, s := range server {
		if s == local[i] {
			continue
		}

		prefix, redacted := strings.CutSuffix(s, redactedArgv)
		if !redacted || !strings.HasPrefix(local[i], prefix) {
			return false
		}
	}

	return true
}
