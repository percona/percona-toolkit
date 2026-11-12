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
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

var reportOrder = []string{
	"Mongos", "Shards", "Instances", "This host", "Arbiter", "OS & Production Checks",
	"Command line arguments", "Startup Options", "Running Ops", "WiredTiger", "Memory",
	"Connections & Profiling", "Security", "Oplog", "Change Streams", "Database Inventory",
	"Cluster wide", "Balancer (per day)", "Not collected",
}

func fullCollectedInfo() *collectedInfo {
	ci := &collectedInfo{}

	v := reflect.ValueOf(ci).Elem()
	for i := 0; i < v.NumField(); i++ {
		f := v.Field(i)
		switch f.Kind() {
		case reflect.Pointer:
			f.Set(reflect.New(f.Type().Elem()))
		case reflect.Slice:
			f.Set(reflect.MakeSlice(f.Type(), 1, 1))
		}
	}

	return ci
}

func headerTitles(out string) []string {
	var titles []string

	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "# ") {
			titles = append(titles, strings.TrimRight(strings.TrimPrefix(line, "# "), "# "))
		}
	}

	return titles
}

func lineContaining(out, substr string) string {
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, substr) {
			return line
		}
	}

	return ""
}

func assertSectionSpacing(t *testing.T, text, label string) {
	t.Helper()

	assert.NotContains(t, text, "\n\n\n", "%s: double blank line", label)

	sections := make(map[string]bool, len(reportOrder))
	for _, title := range reportOrder {
		sections[title] = true
	}

	lines := strings.Split(text, "\n")
	for i := 1; i < len(lines); i++ {
		if rest, ok := strings.CutPrefix(lines[i], "# "); ok && sections[strings.TrimRight(rest, "# ")] {
			assert.Empty(t, lines[i-1], "%s: %q directly under the previous line", label, lines[i])
		}
	}
}

func TestFormatBytes(t *testing.T) {
	tests := []struct {
		in   int64
		want string
	}{
		{0, "0.00 bytes"},
		{1023, "1023.00 bytes"},
		{1024, "1.00 KB"},
		{1536, "1.50 KB"},
		{1048575, "1.00 MB"},
		{3584 << 20, "3.50 GB"},
		{1 << 50, "1.00 PB"},
		{math.MaxInt64, "8.00 EB"},
		{-1536, "-1.50 KB"},
		{math.MinInt64, "-8.00 EB"},
	}

	for _, tt := range tests {
		assert.Equal(t, tt.want, formatBytes(tt.in), "%d", tt.in)
	}
}

func TestFormatSizeAndUnit(t *testing.T) {
	size, unit := sizeAndUnit(1536)
	assert.InDelta(t, 1.5, size, 1e-9)
	assert.Equal(t, "KB", unit)

	size, unit = sizeAndUnit(1024)
	assert.InDelta(t, 1024, size, 1e-9)
	assert.Equal(t, "bytes", unit)

	size, unit = sizeAndUnit(1<<50 + 1<<40)
	assert.InDelta(t, 1.0, size, 0.01)
	assert.Equal(t, "PB", unit)

	_, unit = sizeAndUnit(math.MaxInt64)
	assert.Equal(t, "EB", unit)
}

func TestFormatRate(t *testing.T) {
	tests := []struct {
		in   float64
		want string
	}{
		{0, "0"},
		{4, "4.00"},
		{4.123, "4.12"},
		{62.34, "62.3"},
		{251.04, "251.0"},
		{17265.4, "17265"},
		{17265043, "17265043"},
		{math.NaN(), "-"},
		{math.Inf(1), "-"},
	}

	for _, tt := range tests {
		assert.Equal(t, tt.want, formatRate(tt.in), "%v", tt.in)
	}
}

func TestFormatPct(t *testing.T) {
	assert.Equal(t, "80.1%", formatPct(80.06))
	assert.Equal(t, "0.0%", formatPct(0))
	assert.Equal(t, "141.4%", formatPct(141.42))
}

func TestFormatTime(t *testing.T) {
	assert.Equal(t, "", formatTime(time.Time{}))

	started := time.Date(2026, 10, 27, 18, 11, 40, 0, time.FixedZone("", 2*60*60))
	assert.Equal(t, "2026-10-27 16:11:40 UTC", formatTime(started))
}

func TestFormatDuration(t *testing.T) {
	tests := []struct {
		in   time.Duration
		want string
	}{
		{0, "0.0s"},
		{5 * time.Second, "5.0s"},
		{1500 * time.Millisecond, "1.5s"},
		{59*time.Minute + 59*time.Second, "3599.0s"},
		{3*time.Hour + 5*time.Minute, "3h 05m"},
		{23*time.Hour + 59*time.Minute + 40*time.Second, "1d 00h 00m"},
		{6*24*time.Hour + 3*time.Hour + 12*time.Minute + 40*time.Second, "6d 03h 13m"},
	}

	for _, tt := range tests {
		assert.Equal(t, tt.want, formatDuration(tt.in), "%s", tt.in)
	}
}

func TestHeader(t *testing.T) {
	h := header("OS & Production Checks")
	assert.Len(t, h, 106)
	assert.True(t, strings.HasPrefix(h, "# OS & Production Checks #"), h)
	assert.Equal(t, "#", h[len(h)-1:])

	assert.Len(t, header("Not collected"), 106)

	long := strings.Repeat("x", 110)
	assert.Equal(t, "# "+long, header(long))
}

func TestRenderNoEscaping(t *testing.T) {
	ci := &collectedInfo{
		HostInfo: &hostInfo{
			Hostname:       "db1",
			ProcessName:    "mongod",
			ProcCreateTime: time.Date(2026, 10, 27, 18, 11, 40, 0, time.FixedZone("", 2*60*60)),
			DBPath:         "/data/r&d",
			CmdlineArgs:    []string{"mongod", `--bind_ip="a,b"`, "--setParameter", "x='y'"},
		},
		Errors: []collectError{{
			Section: "Security",
			Item:    "Users/Roles",
			Reason:  `not authorized (needs "find" on <admin.system.users> & more)`,
		}},
	}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	text := string(out)

	for _, escaped := range []string{"&#", "&amp;", "&lt;", "&gt;", "&quot;"} {
		assert.NotContains(t, text, escaped)
	}
	assert.Contains(t, text, "Datadir | /data/r&d")
	assert.Contains(t, text, `--bind_ip="a,b"`)
	assert.Contains(t, text, `x='y'`)
	assert.Contains(t, text, `(needs "find" on <admin.system.users> & more)`)
	assert.Regexp(t, `\+0200|UTC`, lineContaining(text, "Started |"))
}

func TestRenderNilSections(t *testing.T) {
	check := func(t *testing.T, ci *collectedInfo) {
		t.Helper()

		_, err := formatResults(ci, "json")
		require.NoError(t, err)

		_, err = formatResults(ci, "text")
		require.NoError(t, err)

		for _, e := range ci.Errors {
			assert.NotContains(t, e.Reason, "cannot render", e.Section)
		}
	}

	t.Run("none", func(t *testing.T) {
		check(t, fullCollectedInfo())
	})

	typ := reflect.TypeOf(collectedInfo{})
	for i := 0; i < typ.NumField(); i++ {
		field := typ.Field(i)
		if k := field.Type.Kind(); k != reflect.Pointer && k != reflect.Slice {
			continue
		}

		t.Run(field.Name, func(t *testing.T) {
			ci := fullCollectedInfo()
			reflect.ValueOf(ci).Elem().Field(i).SetZero()
			check(t, ci)
		})
	}
}

func TestRenderSectionOrder(t *testing.T) {
	ci := fullCollectedInfo()
	ci.HostInfo.IsArbiter = true
	ci.HostInfo.CmdlineArgs = []string{"mongod"}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)

	pos := map[string]int{}
	for i, title := range headerTitles(string(out)) {
		if _, seen := pos[title]; !seen {
			pos[title] = i
		}
	}

	want := []string{"Arbiter", "Not collected"}
	for _, s := range textSections(ci) {
		if s.show && s.tmpl != "" {
			want = append(want, s.name)
		}
	}
	for _, title := range want {
		assert.Contains(t, pos, title)
	}

	last, lastTitle := -1, ""
	for _, title := range reportOrder {
		p, ok := pos[title]
		if !ok {
			continue
		}
		assert.Greater(t, p, last, "%q after %q", title, lastTitle)
		last, lastTitle = p, title
	}
}

func TestRenderSectionSpacing(t *testing.T) {
	afterHost := []string{
		"OSChecks", "StartupOptions", "RunningOps", "WiredTiger", "Memory", "Connections", "Profiling",
		"SecuritySettings", "OplogInfo", "ChangeStreams", "DatabaseInventory", "ClusterWideInfo", "BalancerStats",
	}

	for _, arbiter := range []bool{false, true} {
		for _, argv := range [][]string{nil, {"mongod", "--port", "27017"}} {
			t.Run(fmt.Sprintf("arbiter %v, %d args", arbiter, len(argv)), func(t *testing.T) {
				full := fullCollectedInfo()
				full.HostInfo.IsArbiter = arbiter
				full.HostInfo.CmdlineArgs = argv
				assertSectionSpacing(t, string(renderText(full)), "all sections")

				for _, name := range afterHost {
					only := &collectedInfo{HostInfo: full.HostInfo, Errors: full.Errors}
					reflect.ValueOf(only).Elem().FieldByName(name).Set(reflect.ValueOf(full).Elem().FieldByName(name))
					assertSectionSpacing(t, string(renderText(only)), "only "+name)

					dropped := *full
					reflect.ValueOf(&dropped).Elem().FieldByName(name).SetZero()
					assertSectionSpacing(t, string(renderText(&dropped)), "without "+name)
				}
			})
		}
	}

	routers := []mongosInstance{{Name: "router:27017", Version: "7.0.14", UpTime: 60}}
	for _, tt := range []struct {
		name     string
		nodeType string
		shards   *shardsInfo
	}{
		{"mongos", typeMongos, &shardsInfo{Shards: []shardEntry{{ID: "rs1", Host: "rs1/db1:27018", Zones: []string{}}}}},
		{"mongos without shards", typeMongos, &shardsInfo{}},
		{"configsvr", "replset", nil},
	} {
		for _, instances := range [][]mongosInstance{routers, nil} {
			t.Run(fmt.Sprintf("%s, %d routers, Instances hidden", tt.name, len(instances)), func(t *testing.T) {
				ci := &collectedInfo{
					MongosInfo: &mongosInfo{Instances: instances},
					ShardsInfo: tt.shards,
					HostInfo:   &hostInfo{Hostname: "db1:27017", NodeType: tt.nodeType},
					Errors:     []collectError{{Section: "Instances", Item: "Instances", Reason: "timed out"}},
				}

				text := string(renderText(ci))
				require.NotContains(t, text, "# Instances")
				assertSectionSpacing(t, text, tt.name)
			})
		}
	}
}

func TestRenderFailingSection(t *testing.T) {
	ci := &collectedInfo{}
	out := string(renderSections(ci, []reportSection{
		{name: "First", tmpl: "\n# First\n", show: true},
		{name: "Broken", tmpl: "\n# Broken\n{{ .Missing }}", data: struct{}{}, show: true},
		{name: "Unparsable", tmpl: "\n# Unparsable\n{{ .Oops ", show: true},
		{name: "Hidden", tmpl: "\n# Hidden\n", show: false},
		{name: "Last", tmpl: "\n# Last\n", show: true},
	}))

	assert.Equal(t, []string{"First", "Last", "Not collected"}, headerTitles(out))
	assert.Regexp(t, `(?m)^ +Broken \| cannot render: `, out)
	assert.Regexp(t, `(?m)^ +Unparsable \| cannot render: `, out)
	assert.Len(t, ci.Errors, 2)
}

func TestRenderNotCollected(t *testing.T) {
	ci := &collectedInfo{
		HostInfo: &hostInfo{Hostname: "db1"},
		Errors: []collectError{
			{Section: "Running Ops", Item: "Running Ops", Code: 13, Reason: "arbiter accepts no logins"},
			{Section: "This host", Item: "Host facts", Code: 13, Reason: "not authorized (needs hostInfo: clusterMonitor)"},
		},
	}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	text := string(out)

	assert.Contains(t, text, "\n"+header("Not collected")+"\n")
	assert.Contains(t, text, fmt.Sprintf("\n%25s | %s\n", "Running Ops", "arbiter accepts no logins"))
	assert.Contains(t, text, fmt.Sprintf("\n%25s | %s\n", "Host facts", "not authorized (needs hostInfo: clusterMonitor)"))

	titles := headerTitles(text)
	assert.Equal(t, "Not collected", titles[len(titles)-1])

	ci.BalancerStats = &proto.BalancerStats{}
	out, err = formatResults(ci, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out), "Drops: 0\n\n# Not collected")

	ci.Errors = nil
	out, err = formatResults(ci, "text")
	require.NoError(t, err)
	assert.NotContains(t, string(out), "# Not collected")
}

func TestRenderInstancesGap(t *testing.T) {
	ci := &collectedInfo{HostInfo: &hostInfo{Hostname: "db1"}}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out), "no replica sets found")

	ci.Errors = []collectError{{Section: "Instances", Item: "Instances", Reason: "timed out"}}
	out, err = formatResults(ci, "text")
	require.NoError(t, err)
	assert.NotContains(t, string(out), "# Instances")

	ci.ReplicaMembers = []proto.Members{{Name: "db1:27017", StateStr: "PRIMARY"}}
	out, err = formatResults(ci, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out), "# Instances")
}
