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
	"encoding/json"
	"fmt"
	"path"
	"regexp"
	"strconv"
	"strings"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

const (
	minOpenFiles = 64000
	minProcesses = 64000
	minTasks     = 64000

	procLimitsNameWidth = 25
	cgroupV2Root        = "/sys/fs/cgroup"
	cgroupV1Pids        = "/sys/fs/cgroup/pids"
	containerScope      = "container view; parent limits not visible"
)

var (
	osReleaseValue = regexp.MustCompile(`^[A-Z_][A-Z0-9_]*="?(.*?)"?$`)
	legacyLogLine  = regexp.MustCompile(`^\d{4}-\d\d-\d\dT\S+\s+([A-Z]\d?)\s+(\S+)\s+\[[^\]]*\]\s?(.*)$`)
	legacyNewEntry = regexp.MustCompile(`^[A-Z]+:`)
)

type osChecks struct {
	OSName                     string
	OSVersion                  string
	KernelVersion              string
	NumCores                   int64
	NumCoresAvailableToProcess int64
	MemSizeMB                  int64
	MemLimitMB                 int64
	NUMAEnabled                bool
	NumNUMANodes               int64
	MaxOpenFiles               int64
	StartupWarnings            []startupWarning
	Local                      *localChecks
	LocalSkipReason            string
	Warnings                   []string
}

type startupWarning struct {
	Severity  string
	Component string
	ID        int64
	Msg       string
	Attr      json.RawMessage
}

type localChecks struct {
	VMMaxMapCount         int64
	VMMaxMapCountMin      int64
	MaxProcesses          int64
	MaxProcessesUnlimited bool
	TasksLimit            string
	TasksLimitScope       string

	runsAsRoot bool
}

func getOSChecks(ctx context.Context, client *mongo.Client, snap *snapshot, hi *hostInfo, b *budget, g *gaps) *osChecks {
	if hi.IsArbiter {
		if !hi.IsLocal || snap.ServerStatusErr != nil {
			return nil
		}

		return buildOSChecks(snap, hi, nil, nil, systemProcFS{}, g)
	}

	lctx, cancel := b.ctx(ctx, nodeCallTimeout)
	defer cancel()

	startupLog, err := runRaw(lctx, client, "admin", bson.D{{Key: "getLog", Value: "startupWarnings"}})

	return buildOSChecks(snap, hi, startupLog, err, systemProcFS{}, g)
}

func buildOSChecks(snap *snapshot, hi *hostInfo, startupLog bson.Raw, logErr error, fs procFS, g *gaps) *osChecks {
	h, extra := snap.HostInfo, hostInfoExtra(snap.HostInfo)
	oc := &osChecks{LocalSkipReason: hi.LocalSkipReason}

	name, _ := rawString(h, "os", "name")
	version, _ := rawString(h, "os", "version")
	oc.OSName, oc.OSVersion = osReleaseText(name), osReleaseText(version)
	oc.KernelVersion, _ = rawString(extra, "kernelVersion")
	oc.NumCores, _ = rawInt64(h, "system", "numCores")
	oc.NumCoresAvailableToProcess, _ = rawInt64(h, "system", "numCoresAvailableToProcess")
	oc.MemSizeMB, _ = rawInt64(h, "system", "memSizeMB")
	oc.MemLimitMB, _ = rawInt64(h, "system", "memLimitMB")
	oc.NUMAEnabled, _ = rawBool(h, "system", "numaEnabled")
	oc.NumNUMANodes, _ = rawInt64(h, "system", "numNumaNodes")
	oc.MaxOpenFiles, _ = rawInt64(extra, "maxOpenFiles")

	switch {
	case logErr != nil:
		g.add("OS & Production Checks", "Startup warnings", "getLog: clusterMonitor", logErr)
	case startupLog != nil:
		lines, _ := rawStrings(startupLog, "log")
		oc.StartupWarnings = parseStartupWarnings(lines)
	}

	if hi.IsLocal {
		pid, _ := rawInt64(snap.ServerStatus, "pid")
		oc.Local = readLocalChecks(fs, int32(pid), snap)
	}

	oc.Warnings = oc.verdicts()

	return oc
}

func hostInfoExtra(h bson.Raw) bson.Raw {
	if nested, ok := rawDoc(h, "extra", "extra"); ok {
		return nested
	}

	extra, _ := rawDoc(h, "extra")

	return extra
}

func readLocalChecks(fs procFS, pid int32, snap *snapshot) *localChecks {
	lc := &localChecks{}

	if data, err := fs.ReadFile("/proc/sys/vm/max_map_count"); err == nil {
		lc.VMMaxMapCount, _ = strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	}

	if conns, ok := snap.maxConns(); ok {
		lc.VMMaxMapCountMin = 2 * conns
	}

	if data, err := fs.ReadFile(fmt.Sprintf("/proc/%d/limits", pid)); err == nil {
		if soft := parseProcLimits(data)["Max processes"]; soft == "unlimited" {
			lc.MaxProcessesUnlimited = true
		} else {
			lc.MaxProcesses, _ = strconv.ParseInt(soft, 10, 64)
		}
	}

	lc.runsAsRoot = processUID(fs, pid) == "0"
	lc.TasksLimit, lc.TasksLimitScope = cgroupTasksLimit(fs, pid)

	return lc
}

func processUID(fs procFS, pid int32) string {
	data, err := fs.ReadFile(fmt.Sprintf("/proc/%d/status", pid))
	if err != nil {
		return ""
	}

	for _, line := range strings.Split(string(data), "\n") {
		if rest, ok := strings.CutPrefix(line, "Uid:"); ok {
			if fields := strings.Fields(rest); len(fields) > 0 {
				return fields[0]
			}
		}
	}

	return ""
}

func parseProcLimits(data []byte) map[string]string {
	limits := map[string]string{}

	for _, line := range strings.Split(string(data), "\n") {
		if len(line) <= procLimitsNameWidth {
			continue
		}

		name := strings.TrimSpace(line[:procLimitsNameWidth])
		fields := strings.Fields(line[procLimitsNameWidth:])
		if name == "" || name == "Limit" || len(fields) == 0 {
			continue
		}

		limits[name] = fields[0]
	}

	return limits
}

func cgroupTasksLimit(fs procFS, pid int32) (string, string) {
	data, err := fs.ReadFile(fmt.Sprintf("/proc/%d/cgroup", pid))
	if err != nil {
		return "", ""
	}

	base, leaf, ok := pidsCgroup(string(data))
	if !ok || !strings.HasPrefix(leaf, "/") || strings.Contains(leaf, "..") {
		return "", ""
	}

	if _, err := fs.ReadFile(path.Join(base, leaf, "cgroup.procs")); err != nil {
		return "", ""
	}

	lowest := int64(-1)

	for dir := leaf; ; dir = path.Dir(dir) {
		if data, err := fs.ReadFile(path.Join(base, dir, "pids.max")); err == nil {
			n, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
			if err == nil && (lowest < 0 || n < lowest) {
				lowest = n
			}
		}

		if dir == "/" {
			break
		}
	}

	value := "unlimited"
	if lowest >= 0 {
		value = strconv.FormatInt(lowest, 10)
	}

	if leaf == "/" {
		return value, containerScope
	}

	return value, ""
}

func pidsCgroup(data string) (string, string, bool) {
	var base, leaf string

	for _, line := range strings.Split(data, "\n") {
		parts := strings.SplitN(line, ":", 3)
		if len(parts) != 3 {
			continue
		}

		if parts[0] == "0" && parts[1] == "" {
			base, leaf = cgroupV2Root, parts[2]

			continue
		}

		for _, controller := range strings.Split(parts[1], ",") {
			if controller == "pids" {
				return cgroupV1Pids, parts[2], true
			}
		}
	}

	return base, leaf, base != ""
}

func parseStartupWarnings(lines []string) []startupWarning {
	out := []startupWarning{}
	open := -1

	for _, raw := range lines {
		line := strings.TrimRight(raw, "\r\n")
		if strings.TrimSpace(line) == "" {
			open = -1

			continue
		}

		if w, ok := parseJSONWarning(line); ok {
			out = append(out, w)
			open = -1

			continue
		}

		m := legacyLogLine.FindStringSubmatch(line)
		if m == nil {
			out = append(out, startupWarning{Msg: line})
			open = -1

			continue
		}

		msg := strings.TrimSpace(m[3])
		text, continued := strings.CutPrefix(msg, "**")
		text = strings.TrimSpace(text)

		switch {
		case text == "":
			open = -1
		case continued && open >= 0 && !legacyNewEntry.MatchString(text):
			out[open].Msg += " " + text
		case continued:
			out = append(out, startupWarning{Severity: m[1], Component: m[2], Msg: text})
			open = len(out) - 1
		default:
			out = append(out, startupWarning{Severity: m[1], Component: m[2], Msg: msg})
			open = -1
		}
	}

	return out
}

func parseJSONWarning(line string) (startupWarning, bool) {
	if !strings.HasPrefix(strings.TrimSpace(line), "{") {
		return startupWarning{}, false
	}

	var entry struct {
		Severity  string          `json:"s"`
		Component string          `json:"c"`
		ID        int64           `json:"id"`
		Msg       string          `json:"msg"`
		Attr      json.RawMessage `json:"attr"`
	}
	if err := json.Unmarshal([]byte(line), &entry); err != nil || entry.Msg == "" {
		return startupWarning{}, false
	}

	w := startupWarning{Severity: entry.Severity, Component: entry.Component, ID: entry.ID, Msg: entry.Msg}

	var attr bytes.Buffer
	if len(entry.Attr) > 0 && string(entry.Attr) != "null" && json.Compact(&attr, entry.Attr) == nil {
		w.Attr = json.RawMessage(attr.Bytes())
	}

	return w, true
}

func osReleaseText(s string) string {
	s = strings.TrimSpace(s)
	if m := osReleaseValue.FindStringSubmatch(s); m != nil {
		return strings.TrimSpace(m[1])
	}

	return s
}

func (w startupWarning) Text() string {
	if len(w.Attr) == 0 {
		return w.Msg
	}

	return w.Msg + " " + string(w.Attr)
}

func (o *osChecks) OSSummary() string {
	switch {
	case o.OSVersion == "" || strings.HasPrefix(o.OSVersion, "Kernel ") || strings.Contains(o.OSName, o.OSVersion):
		return o.OSName
	case o.OSName == "":
		return o.OSVersion
	}

	return o.OSName + " " + o.OSVersion
}

func (o *osChecks) CPUSummary() string {
	if o.NumCores <= 0 {
		return ""
	}

	if o.NumCoresAvailableToProcess > 0 && o.NumCoresAvailableToProcess < o.NumCores {
		return fmt.Sprintf("%d (%d in CPU affinity)", o.NumCores, o.NumCoresAvailableToProcess)
	}

	return strconv.FormatInt(o.NumCores, 10)
}

func (o *osChecks) RAMSummary() string {
	if o.MemSizeMB <= 0 {
		return ""
	}

	if o.MemLimitMB > 0 && o.MemLimitMB < o.MemSizeMB {
		return fmt.Sprintf("%d MB (limit %d MB)", o.MemSizeMB, o.MemLimitMB)
	}

	return fmt.Sprintf("%d MB", o.MemSizeMB)
}

func (o *osChecks) NUMASummary() string {
	switch {
	case o.NumCores <= 0:
		return ""
	case !o.NUMAEnabled:
		return "off or interleaved"
	case o.NumNUMANodes > 0:
		return fmt.Sprintf("on, not interleaved (%d nodes)", o.NumNUMANodes)
	}

	return "on, not interleaved"
}

func (o *osChecks) NUMAWarning() string {
	if !o.NUMAEnabled || o.NUMASummary() == "" {
		return ""
	}

	return "start mongod with numactl --interleave=all"
}

func (o *osChecks) OpenFilesWarning() string {
	if o.MaxOpenFiles <= 0 || o.MaxOpenFiles >= minOpenFiles {
		return ""
	}

	return fmt.Sprintf("below %d", minOpenFiles)
}

func (o *osChecks) StartupWarningsSummary() string {
	switch {
	case o.StartupWarnings == nil:
		return ""
	case len(o.StartupWarnings) == 0:
		return "none"
	}

	return strconv.Itoa(len(o.StartupWarnings))
}

func (o *osChecks) verdicts() []string {
	out := []string{}

	if w := o.OpenFilesWarning(); w != "" {
		out = append(out, fmt.Sprintf("Open files limit %d is %s", o.MaxOpenFiles, w))
	}

	if w := o.NUMAWarning(); w != "" {
		out = append(out, fmt.Sprintf("NUMA %s: %s", o.NUMASummary(), w))
	}

	if l := o.Local; l != nil {
		if w := l.MaxMapCountWarning(); w != "" {
			out = append(out, fmt.Sprintf("vm.max_map_count %d is %s", l.VMMaxMapCount, w))
		}

		if w := l.MaxProcessesWarning(); w != "" {
			out = append(out, fmt.Sprintf("Max processes (mongod) %d is %s", l.MaxProcesses, w))
		}

		if w := l.TasksLimitWarning(); w != "" {
			out = append(out, fmt.Sprintf("Tasks limit (cgroup) %s is %s", l.TasksLimit, w))
		}
	}

	return out
}

func (l *localChecks) MaxMapCountText() string {
	if l.VMMaxMapCount <= 0 {
		return "not readable"
	}

	return strconv.FormatInt(l.VMMaxMapCount, 10)
}

func (l *localChecks) MaxMapCountWarning() string {
	if l.VMMaxMapCount <= 0 || l.VMMaxMapCountMin <= 0 || l.VMMaxMapCount >= l.VMMaxMapCountMin {
		return ""
	}

	return fmt.Sprintf("below 2 x max connections (%d)", l.VMMaxMapCountMin)
}

func (l *localChecks) MaxProcessesText() string {
	switch {
	case l.MaxProcessesUnlimited:
		return "unlimited (soft, per user)"
	case l.MaxProcesses > 0:
		return fmt.Sprintf("%d (soft, per user)", l.MaxProcesses)
	}

	return "not readable"
}

func (l *localChecks) MaxProcessesWarning() string {
	if l.runsAsRoot || l.MaxProcessesUnlimited || l.MaxProcesses <= 0 || l.MaxProcesses >= minProcesses {
		return ""
	}

	return fmt.Sprintf("below %d", minProcesses)
}

func (l *localChecks) TasksLimitText() string {
	switch {
	case l.TasksLimit == "":
		return "not visible"
	case l.TasksLimitScope != "":
		return l.TasksLimit + " (" + l.TasksLimitScope + ")"
	}

	return l.TasksLimit
}

func (l *localChecks) TasksLimitWarning() string {
	n, err := strconv.ParseInt(l.TasksLimit, 10, 64)
	if err != nil || n >= minTasks {
		return ""
	}

	return fmt.Sprintf("below %d", minTasks)
}
