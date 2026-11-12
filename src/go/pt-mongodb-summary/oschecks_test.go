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
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
)

const procLimits = `Limit                     Soft Limit           Hard Limit           Units
Max cpu time              unlimited            unlimited            seconds
Max file size             unlimited            unlimited            bytes
Max stack size            8388608              unlimited            bytes
Max processes             4096                 64000                processes
Max open files            1024                 524288               files
Max locked memory         8388608              8388608              bytes
Max nice priority         0                    0
Max realtime timeout      unlimited            unlimited            us
`

func TestParseProcLimits(t *testing.T) {
	limits := parseProcLimits([]byte(procLimits))
	assert.Equal(t, "4096", limits["Max processes"])
	assert.Equal(t, "1024", limits["Max open files"])
	assert.Equal(t, "unlimited", limits["Max cpu time"])
	assert.Equal(t, "0", limits["Max nice priority"])
	assert.NotContains(t, limits, "Limit")

	assert.Empty(t, parseProcLimits(nil))
	assert.Empty(t, parseProcLimits([]byte("short\n")))
}

func TestCgroupTasksLimit(t *testing.T) {
	tests := []struct {
		name  string
		files map[string]string
		value string
		scope string
	}{
		{
			name: "v2 leaf",
			files: map[string]string{
				"/proc/7/cgroup": "0::/system.slice/mongod.service\n",
				"/sys/fs/cgroup/system.slice/mongod.service/cgroup.procs": "7\n",
				"/sys/fs/cgroup/system.slice/mongod.service/pids.max":     "4915\n",
				"/sys/fs/cgroup/system.slice/pids.max":                    "max\n",
			},
			value: "4915",
		},
		{
			name: "leaf max under a lower parent",
			files: map[string]string{
				"/proc/7/cgroup": "0::/system.slice/mongod.service\n",
				"/sys/fs/cgroup/system.slice/mongod.service/cgroup.procs": "7\n",
				"/sys/fs/cgroup/system.slice/mongod.service/pids.max":     "max\n",
				"/sys/fs/cgroup/system.slice/pids.max":                    "1024\n",
			},
			value: "1024",
		},
		{
			name: "all max",
			files: map[string]string{
				"/proc/7/cgroup": "0::/system.slice/mongod.service\n",
				"/sys/fs/cgroup/system.slice/mongod.service/cgroup.procs": "7\n",
				"/sys/fs/cgroup/system.slice/mongod.service/pids.max":     "max\n",
				"/sys/fs/cgroup/system.slice/pids.max":                    "max\n",
			},
			value: "unlimited",
		},
		{
			name: "no pids controller",
			files: map[string]string{
				"/proc/7/cgroup":                         "0::/user.slice\n",
				"/sys/fs/cgroup/user.slice/cgroup.procs": "7\n",
			},
			value: "unlimited",
		},
		{
			name: "private cgroup namespace",
			files: map[string]string{
				"/proc/7/cgroup":              "0::/\n",
				"/sys/fs/cgroup/cgroup.procs": "1\n7\n",
				"/sys/fs/cgroup/pids.max":     "2048\n",
			},
			value: "2048",
			scope: "container view; parent limits not visible",
		},
		{
			name: "private cgroup namespace without a limit",
			files: map[string]string{
				"/proc/7/cgroup":              "0::/\n",
				"/sys/fs/cgroup/cgroup.procs": "1\n7\n",
			},
			value: "unlimited",
			scope: "container view; parent limits not visible",
		},
		{
			name: "outside this cgroup namespace",
			files: map[string]string{
				"/proc/7/cgroup":                       "0::/../../system.slice/docker-1.scope\n",
				"/sys/fs/cgroup/cgroup.procs":          "1\n",
				"/sys/fs/cgroup/system.slice/pids.max": "100\n",
			},
		},
		{
			name: "leaf not visible",
			files: map[string]string{
				"/proc/7/cgroup":                       "0::/system.slice/mongod.service\n",
				"/sys/fs/cgroup/system.slice/pids.max": "100\n",
			},
		},
		{
			name: "v1 pids hierarchy",
			files: map[string]string{
				"/proc/7/cgroup": "12:pids:/system.slice/mongod.service\n" +
					"4:cpu,cpuacct:/system.slice/mongod.service\n0::/system.slice/mongod.service\n",
				"/sys/fs/cgroup/pids/system.slice/mongod.service/cgroup.procs": "7\n",
				"/sys/fs/cgroup/pids/system.slice/mongod.service/pids.max":     "512\n",
				"/sys/fs/cgroup/pids/system.slice/pids.max":                    "max\n",
				"/sys/fs/cgroup/system.slice/mongod.service/pids.max":          "1\n",
			},
			value: "512",
		},
		{
			name:  "cgroup file not readable",
			files: map[string]string{},
		},
		{
			name:  "garbage",
			files: map[string]string{"/proc/7/cgroup": "garbage\n"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			value, scope := cgroupTasksLimit(fakeProcFS{files: tt.files}, 7)
			assert.Equal(t, tt.value, value)
			assert.Equal(t, tt.scope, scope)
		})
	}
}

func TestOSChecksSummaries(t *testing.T) {
	tests := []struct {
		name, version, want string
	}{
		{"Red Hat Enterprise Linux release 9.8 (Plow)", "Kernel 7.2.11-200.fc44.x86_64", "Red Hat Enterprise Linux release 9.8 (Plow)"},
		{"Ubuntu", "22.04", "Ubuntu 22.04"},
		{`PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"`, "Kernel 6.1.0-18-amd64", "Debian GNU/Linux 12 (bookworm)"},
		{`DISTRIB_DESCRIPTION="Ubuntu 22.04.4 LTS"`, "22.04", "Ubuntu 22.04.4 LTS"},
		{"Ubuntu 22.04.4 LTS", "22.04.4", "Ubuntu 22.04.4 LTS"},
		{"macOS", "14.4", "macOS 14.4"},
		{"", "10.0 (build 17763)", "10.0 (build 17763)"},
		{"Foo=bar", "", "Foo=bar"},
		{"", "", ""},
	}
	for _, tt := range tests {
		snap := &snapshot{HostInfo: mustRaw(t, bson.D{{Key: "os", Value: bson.D{
			{Key: "name", Value: tt.name}, {Key: "version", Value: tt.version},
		}}})}
		oc := buildOSChecks(snap, &hostInfo{}, nil, nil, fakeProcFS{}, &gaps{})
		assert.Equal(t, tt.want, oc.OSSummary(), "%q %q", tt.name, tt.version)
	}

	oc := &osChecks{NumCores: 8, NumCoresAvailableToProcess: 2, MemSizeMB: 31958, MemLimitMB: 8192, NUMAEnabled: true, NumNUMANodes: 2}
	assert.Equal(t, "8 (2 in CPU affinity)", oc.CPUSummary())
	assert.Equal(t, "31958 MB (limit 8192 MB)", oc.RAMSummary())
	assert.Equal(t, "on, not interleaved (2 nodes)", oc.NUMASummary())
	assert.Equal(t, "start mongod with numactl --interleave=all", oc.NUMAWarning())

	oc = &osChecks{NumCores: 8, NumCoresAvailableToProcess: 8, MemSizeMB: 31958, MemLimitMB: 31958, NUMAEnabled: true}
	assert.Equal(t, "8", oc.CPUSummary())
	assert.Equal(t, "31958 MB", oc.RAMSummary())
	assert.Equal(t, "on, not interleaved", oc.NUMASummary())

	oc = &osChecks{NumCores: 8, NumCoresAvailableToProcess: -1, MemSizeMB: 31958, MemLimitMB: 0}
	assert.Equal(t, "8", oc.CPUSummary())
	assert.Equal(t, "31958 MB", oc.RAMSummary())
	assert.Equal(t, "off or interleaved", oc.NUMASummary())
	assert.Empty(t, oc.NUMAWarning())

	oc = &osChecks{}
	assert.Empty(t, oc.CPUSummary())
	assert.Empty(t, oc.RAMSummary())
	assert.Empty(t, oc.NUMASummary())
	assert.Empty(t, oc.OpenFilesWarning())
	assert.Empty(t, oc.StartupWarningsSummary())

	oc.StartupWarnings = []startupWarning{}
	assert.Equal(t, "none", oc.StartupWarningsSummary())

	snap := &snapshot{HostInfo: mustRaw(t, bson.D{{Key: "system", Value: bson.D{
		{Key: "numCores", Value: int32(64)},
		{Key: "numaEnabled", Value: true},
		{Key: "numNumaNodes", Value: int32(4)},
	}}})}
	oc = buildOSChecks(snap, &hostInfo{}, nil, nil, fakeProcFS{}, &gaps{})
	assert.Equal(t, []string{"NUMA on, not interleaved (4 nodes): start mongod with numactl --interleave=all"}, oc.Warnings)

	out, err := formatResults(&collectedInfo{OSChecks: oc}, "text")
	require.NoError(t, err)
	assert.Contains(t, string(out),
		"                     NUMA | on, not interleaved (4 nodes)  [WARNING: start mongod with numactl --interleave=all]")
}
