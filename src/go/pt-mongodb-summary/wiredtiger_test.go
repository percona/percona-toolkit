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
	"strings"
	"testing"
	"time"

	"github.com/AlekSi/pointer"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
)

type wtCache struct {
	Max, Used, Dirty, Updates                        int64
	PagesRead, BytesRead, PagesWritten, BytesWritten int64
	Unmodified, Modified, AppEvicted                 int64
}

var (
	wtStart = wtCache{
		Max: 8 << 30, Used: 6 << 30, Dirty: 300 << 20, Updates: 100 << 20,
		PagesRead: 100, BytesRead: 1000, PagesWritten: 10, BytesWritten: 500,
		Unmodified: 7, Modified: 3, AppEvicted: 2,
	}
	wtEnd = wtCache{
		Max: 8 << 30, Used: 7 << 30, Dirty: 400 << 20, Updates: 200 << 20,
		PagesRead: 3100, BytesRead: 1000 + 100<<20, PagesWritten: 630, BytesWritten: 500 + 20<<20,
		Unmodified: 2985, Modified: 601, AppEvicted: 26,
	}
)

func (c wtCache) doc() bson.D {
	return bson.D{
		{Key: "bytes allocated for updates", Value: c.Updates},
		{Key: "bytes currently in the cache", Value: c.Used},
		{Key: "bytes read into cache", Value: c.BytesRead},
		{Key: "bytes written from cache", Value: c.BytesWritten},
		{Key: "maximum bytes configured", Value: c.Max},
		{Key: "modified pages evicted", Value: c.Modified},
		{Key: "pages evicted by application threads", Value: c.AppEvicted},
		{Key: "pages read into cache", Value: c.PagesRead},
		{Key: "pages written from cache", Value: c.PagesWritten},
		{Key: "tracked dirty bytes in the cache", Value: c.Dirty},
		{Key: "unmodified pages evicted", Value: c.Unmodified},
	}
}

type wtStatus struct {
	Engine   string
	StatsKey string
	Host     string
	Pid      int64
	UptimeMs int64
	Cache    bson.D
	Wait     any
}

func newWTStatus(uptimeMs int64, cache bson.D, wait int64) wtStatus {
	return wtStatus{
		Engine: "wiredTiger", StatsKey: "wiredTiger", Host: "db:27017", Pid: 7,
		UptimeMs: uptimeMs, Cache: cache, Wait: wait,
	}
}

func (s wtStatus) raw(t *testing.T) bson.Raw {
	t.Helper()

	doc := bson.D{
		{Key: "host", Value: s.Host},
		{Key: "pid", Value: s.Pid},
		{Key: "uptimeMillis", Value: s.UptimeMs},
		{Key: "storageEngine", Value: bson.D{{Key: "name", Value: s.Engine}}},
	}
	if s.StatsKey != "" {
		doc = append(doc, bson.E{Key: s.StatsKey, Value: bson.D{
			{Key: "cache", Value: s.Cache},
			{Key: "thread-yield", Value: bson.D{{Key: "application thread time waiting for cache (usecs)", Value: s.Wait}}},
		}})
	}

	return mustRaw(t, doc)
}

func withKeyRenamed(d bson.D, from, to string) bson.D {
	out := make(bson.D, 0, len(d))
	for _, e := range d {
		if e.Key == from {
			e.Key = to
		}
		out = append(out, e)
	}

	return out
}

func withoutKey(d bson.D, key string) bson.D {
	out := make(bson.D, 0, len(d))
	for _, e := range d {
		if e.Key != key {
			out = append(out, e)
		}
	}

	return out
}

func withDoubles(d bson.D) bson.D {
	out := make(bson.D, 0, len(d))
	for _, e := range d {
		if v, ok := e.Value.(int64); ok {
			e.Value = float64(v)
		}
		out = append(out, e)
	}

	return out
}

func wtRatesSet(t *testing.T, statuses ...wtStatus) (*snapshot, opSampleSet) {
	t.Helper()

	set := opSampleSet{}
	for _, s := range statuses {
		set.Docs = append(set.Docs, s.raw(t))
	}

	return &snapshot{ServerStatus: set.Docs[0]}, set
}

func TestBuildWiredTiger(t *testing.T) {
	snap, set := wtRatesSet(t, newWTStatus(10000, wtStart.doc(), 1000), newWTStatus(12000, wtEnd.doc(), 71400))
	g := &gaps{}

	wt := buildWiredTiger(snap, set, g)

	assert.Equal(t, &wiredTigerInfo{
		Engine:                  "wiredTiger",
		CacheMaxBytes:           8 << 30,
		CacheUsedBytes:          6 << 30,
		CacheUsedPct:            75,
		CacheFreeBytes:          2 << 30,
		CacheFreePct:            25,
		CacheDirtyBytes:         300 << 20,
		CacheDirtyPct:           300.0 / 8192 * 100,
		CacheUpdatesBytes:       pointer.ToInt64(100 << 20),
		CacheUpdatesPct:         100.0 / 8192 * 100,
		Window:                  2 * time.Second,
		PagesReadIntoCache:      wtCounter{Total: 100, PerSec: 1500},
		BytesReadIntoCache:      wtCounter{Total: 1000, PerSec: 50 << 20},
		PagesWrittenFromCache:   wtCounter{Total: 10, PerSec: 310},
		BytesWrittenFromCache:   wtCounter{Total: 500, PerSec: 10 << 20},
		UnmodifiedPagesEvicted:  wtCounter{Total: 7, PerSec: 1489},
		ModifiedPagesEvicted:    wtCounter{Total: 3, PerSec: 299},
		AppThreadEvictions:      wtCounter{Total: 2, PerSec: 12},
		AppThreadCacheWaitUsecs: wtCounter{Total: 1000, PerSec: 35200},
	}, wt)
	assert.Empty(t, g.list)
}

func TestBuildWiredTigerRatesFirstToLast(t *testing.T) {
	middle := wtStart
	middle.PagesRead, middle.Modified = 1, 999999
	snap, set := wtRatesSet(t,
		newWTStatus(10000, wtStart.doc(), 1000),
		newWTStatus(11000, middle.doc(), 5),
		newWTStatus(12000, wtEnd.doc(), 71400),
	)

	wt := buildWiredTiger(snap, set, &gaps{})
	require.NotNil(t, wt)

	assert.Equal(t, 2*time.Second, wt.Window)
	assert.Equal(t, wtCounter{Total: 100, PerSec: 1500}, wt.PagesReadIntoCache)
	assert.Equal(t, wtCounter{Total: 3, PerSec: 299}, wt.ModifiedPagesEvicted)
	assert.Equal(t, wtCounter{Total: 1000, PerSec: 35200}, wt.AppThreadCacheWaitUsecs)
}

func TestBuildWiredTigerNoRates(t *testing.T) {
	restarted := newWTStatus(500, wtEnd.doc(), 71400)
	otherHost := newWTStatus(12000, wtEnd.doc(), 71400)
	otherHost.Host = "other:27017"
	otherPid := newWTStatus(12000, wtEnd.doc(), 71400)
	otherPid.Pid = 8
	lower := wtEnd
	lower.PagesRead = 50

	tests := map[string][]wtStatus{
		"sampler off":     nil,
		"no sample":       {},
		"under 1s":        {newWTStatus(10999, wtEnd.doc(), 71400)},
		"restart":         {restarted},
		"host change":     {otherHost},
		"pid change":      {otherPid},
		"counter dropped": {newWTStatus(12000, lower.doc(), 71400)},
	}

	for name, later := range tests {
		t.Run(name, func(t *testing.T) {
			snap, set := wtRatesSet(t, append([]wtStatus{newWTStatus(10000, wtStart.doc(), 1000)}, later...)...)
			if later == nil {
				set = opSampleSet{}
			}

			wt := buildWiredTiger(snap, set, &gaps{})
			require.NotNil(t, wt)

			assert.Zero(t, wt.Window)
			for _, c := range []wtCounter{
				wt.PagesReadIntoCache, wt.BytesReadIntoCache, wt.PagesWrittenFromCache, wt.BytesWrittenFromCache,
				wt.UnmodifiedPagesEvicted, wt.ModifiedPagesEvicted, wt.AppThreadEvictions, wt.AppThreadCacheWaitUsecs,
			} {
				assert.Zero(t, c.PerSec)
			}
			assert.Equal(t, int64(100), wt.PagesReadIntoCache.Total)
			assert.Equal(t, int64(6<<30), wt.CacheUsedBytes)
		})
	}
}

func TestBuildWiredTigerEvictionKeys(t *testing.T) {
	const attempts = "page evict attempts by application threads"

	start := withKeyRenamed(wtStart.doc(), "pages evicted by application threads", attempts)
	end := withKeyRenamed(wtEnd.doc(), "pages evicted by application threads", attempts)

	snap, set := wtRatesSet(t, newWTStatus(10000, start, 0), newWTStatus(12000, end, 0))
	wt := buildWiredTiger(snap, set, &gaps{})
	require.NotNil(t, wt)
	assert.Equal(t, wtCounter{Total: 2, PerSec: 12}, wt.AppThreadEvictions)

	both := append(wtStart.doc(), bson.E{Key: attempts, Value: int64(100)})
	bothEnd := append(wtEnd.doc(), bson.E{Key: attempts, Value: int64(130)})
	snap, set = wtRatesSet(t, newWTStatus(10000, both, 0), newWTStatus(12000, bothEnd, 0))
	wt = buildWiredTiger(snap, set, &gaps{})
	require.NotNil(t, wt)
	assert.Equal(t, wtCounter{Total: 102, PerSec: 27}, wt.AppThreadEvictions)
}

func TestBuildWiredTigerDoubles(t *testing.T) {
	s0 := newWTStatus(10000, withDoubles(wtStart.doc()), 1000)
	s0.Wait = float64(1000)
	s1 := newWTStatus(12000, withDoubles(wtEnd.doc()), 71400)
	s1.Wait = float64(71400)
	snap, set := wtRatesSet(t, s0, s1)

	wt := buildWiredTiger(snap, set, &gaps{})
	require.NotNil(t, wt)

	assert.Equal(t, int64(8<<30), wt.CacheMaxBytes)
	assert.Equal(t, int64(6<<30), wt.CacheUsedBytes)
	assert.Equal(t, int64(300<<20), wt.CacheDirtyBytes)
	assert.Equal(t, pointer.ToInt64(100<<20), wt.CacheUpdatesBytes)
	assert.Equal(t, wtCounter{Total: 1000, PerSec: 50 << 20}, wt.BytesReadIntoCache)
	assert.Equal(t, wtCounter{Total: 1000, PerSec: 35200}, wt.AppThreadCacheWaitUsecs)
}

func TestBuildWiredTigerShapes(t *testing.T) {
	noUpdates := newWTStatus(10000, withoutKey(wtStart.doc(), "bytes allocated for updates"), 0)
	wt := buildWiredTiger(&snapshot{ServerStatus: noUpdates.raw(t)}, opSampleSet{}, &gaps{})
	require.NotNil(t, wt)
	assert.Nil(t, wt.CacheUpdatesBytes)
	assert.Zero(t, wt.CacheUpdatesPct)

	over := wtStart
	over.Used = 9 << 30
	wt = buildWiredTiger(&snapshot{ServerStatus: newWTStatus(10000, over.doc(), 0).raw(t)}, opSampleSet{}, &gaps{})
	require.NotNil(t, wt)
	assert.Equal(t, 112.5, wt.CacheUsedPct)
	assert.Zero(t, wt.CacheFreeBytes)
	assert.Zero(t, wt.CacheFreePct)

	inMemory := newWTStatus(10000, wtStart.doc(), 0)
	inMemory.Engine, inMemory.StatsKey = "inMemory", "inMemory"
	g := &gaps{}
	wt = buildWiredTiger(&snapshot{ServerStatus: inMemory.raw(t)}, opSampleSet{}, g)
	require.NotNil(t, wt)
	assert.Equal(t, "inMemory", wt.Engine)
	assert.Equal(t, int64(8<<30), wt.CacheMaxBytes)
	assert.Equal(t, int64(100), wt.PagesReadIntoCache.Total)
	assert.Empty(t, g.list)

	for _, engine := range []string{"mmapv1", "devnull", ""} {
		other := newWTStatus(10000, wtStart.doc(), 0)
		other.Engine, other.StatsKey = engine, ""
		g := &gaps{}
		assert.Nil(t, buildWiredTiger(&snapshot{ServerStatus: other.raw(t)}, opSampleSet{}, g), engine)
		assert.Empty(t, g.list, engine)
	}

	g = &gaps{}
	assert.Nil(t, buildWiredTiger(&snapshot{}, opSampleSet{}, g))
	assert.Empty(t, g.list)
}

func TestBuildWiredTigerStatsMissing(t *testing.T) {
	for _, engine := range []string{"wiredTiger", "inMemory"} {
		t.Run(engine, func(t *testing.T) {
			s := newWTStatus(10000, nil, 0)
			s.Engine, s.StatsKey = engine, ""
			g := &gaps{}

			assert.Nil(t, buildWiredTiger(&snapshot{ServerStatus: s.raw(t)}, opSampleSet{}, g))

			require.Len(t, g.list, 1)
			assert.Equal(t, "WiredTiger", g.list[0].Section)
			assert.Equal(t, "WiredTiger", g.list[0].Item)
			assert.Contains(t, g.list[0].Reason, "serverStatus returned no "+engine+" statistics")
		})
	}

	s := newWTStatus(10000, withoutKey(wtStart.doc(), "maximum bytes configured"), 0)
	g := &gaps{}
	assert.Nil(t, buildWiredTiger(&snapshot{ServerStatus: s.raw(t)}, opSampleSet{}, g))
	assert.Len(t, g.list, 1)
}

func tcmallocStatus(t *testing.T, mem, tcmalloc bson.D) *snapshot {
	t.Helper()

	doc := bson.D{{Key: "host", Value: "db:27017"}}
	if mem != nil {
		doc = append(doc, bson.E{Key: "mem", Value: mem})
	}
	if tcmalloc != nil {
		doc = append(doc, bson.E{Key: "tcmalloc", Value: tcmalloc})
	}

	return &snapshot{ServerStatus: mustRaw(t, doc)}
}

func TestBuildMemoryShapes(t *testing.T) {
	gperf := bson.D{
		{Key: "generic", Value: bson.D{
			{Key: "current_allocated_bytes", Value: int64(900)},
			{Key: "heap_size", Value: int64(1200)},
		}},
		{Key: "tcmalloc", Value: bson.D{
			{Key: "pageheap_free_bytes", Value: int32(50)},
			{Key: "pageheap_unmapped_bytes", Value: int32(10)},
			{Key: "total_free_bytes", Value: int64(77777)},
			{Key: "central_cache_free_bytes", Value: int32(20)},
			{Key: "transfer_cache_free_bytes", Value: 20.0},
			{Key: "thread_cache_free_bytes", Value: int64(10)},
			{Key: "release_rate", Value: 0.5},
		}},
	}
	mem := bson.D{{Key: "bits", Value: int32(64)}, {Key: "resident", Value: int32(12)}, {Key: "supported", Value: true}}

	m := buildMemory(tcmallocStatus(t, mem, gperf))
	require.NotNil(t, m)
	assert.Equal(t, pointer.ToInt64(12), m.ResidentMB)
	assert.Equal(t, &tcmallocInfo{
		AllocatedBytes:    900,
		HeapSizeBytes:     1200,
		PageheapFreeBytes: 50,
		CacheFreeBytes:    50,
		UnmappedBytes:     10,
		FreePct:           10,
	}, m.TCMalloc)

	unsupported := bson.D{{Key: "bits", Value: int32(64)}, {Key: "supported", Value: false}}
	m = buildMemory(tcmallocStatus(t, unsupported, gperf))
	require.NotNil(t, m)
	assert.Nil(t, m.ResidentMB)
	assert.NotNil(t, m.TCMalloc)

	m = buildMemory(tcmallocStatus(t, mem, nil))
	require.NotNil(t, m)
	assert.Equal(t, pointer.ToInt64(12), m.ResidentMB)
	assert.Nil(t, m.TCMalloc)

	noAllocated := bson.D{{Key: "generic", Value: bson.D{{Key: "heap_size", Value: int64(1200)}}}}
	m = buildMemory(tcmallocStatus(t, mem, noAllocated))
	require.NotNil(t, m)
	assert.Nil(t, m.TCMalloc)

	perCPU := append(bson.D{{Key: "usingPerCPUCaches", Value: false}}, gperf...)
	m = buildMemory(tcmallocStatus(t, nil, perCPU))
	require.NotNil(t, m)
	assert.Nil(t, m.ResidentMB)
	require.NotNil(t, m.TCMalloc.PerCPUCaches)
	assert.False(t, *m.TCMalloc.PerCPUCaches)

	assert.Nil(t, buildMemory(tcmallocStatus(t, unsupported, nil)))
	assert.Nil(t, buildMemory(&snapshot{}))
}

func sectionBodyLines(out, title string) []string {
	lines := strings.Split(out, "\n")
	for i, line := range lines {
		if line != header(title) {
			continue
		}

		var body []string
		for _, l := range lines[i+1:] {
			if l == "" || strings.HasPrefix(l, "# ") {
				break
			}
			body = append(body, l)
		}

		return body
	}

	return nil
}

func TestFormatWiredTigerRates(t *testing.T) {
	snap, set := wtRatesSet(t, newWTStatus(10000, wtStart.doc(), 1000), newWTStatus(12000, wtEnd.doc(), 71400))
	ci := &collectedInfo{WiredTiger: buildWiredTiger(snap, set, &gaps{})}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)

	assert.Equal(t, []string{
		"           Storage Engine | wiredTiger",
		"               Cache Size | 8.00 GB",
		"               Cache Used | 6.00 GB (75.0%)",
		"               Cache Free | 2.00 GB (25.0%)",
		"              Cache Dirty | 300.00 MB (3.7%)",
		"            Cache Updates | 100.00 MB (1.2%)",
		"              Rate Window | 2.0s",
		"          Read Into Cache | 1500 pages/s, 50.00 MB/s uncompressed",
		"       Written From Cache | 310.0 pages/s, 10.00 MB/s uncompressed",
		" Unmodified Pages Evicted | 1489/s",
		"   Modified Pages Evicted | 299.0/s",
		"App Thread Evict Attempts | 12.0/s",
		" App Thread Wait on Cache | 35.2 ms/s",
	}, sectionBodyLines(string(out), "WiredTiger"))
}

func TestFormatRunningOpsPartialAndGauges(t *testing.T) {
	set := pointSet(t, cmdPoint(1000, 10), cmdPoint(2000, 20), cmdPoint(3000, 40))
	set.Err = errors.New("boom")
	oc, err := summarizeRunningOps(set, time.Second)
	require.NoError(t, err)

	ci := &collectedInfo{
		RunningOps: oc,
		WiredTiger: &wiredTigerInfo{Engine: "inMemory", CacheMaxBytes: 1 << 30},
		Memory:     &memoryInfo{TCMalloc: &tcmallocInfo{AllocatedBytes: 1 << 20}},
	}

	out, err := formatResults(ci, "text")
	require.NoError(t, err)
	text := string(out)

	assert.Contains(t, text, "\n"+`Per second over 2.0s of sampling; "Since start" = average over 3.0s of uptime`+"\n"+
		"partial: 2 of 3 intervals (last error: boom)\n"+
		"Type           Min/s       Max/s       Avg/s   Since start/day\n")
	assert.Equal(t, []string{
		"           Storage Engine | inMemory",
		"               Cache Size | 1.00 GB",
		"               Cache Used | 0.00 bytes (0.0%)",
		"               Cache Free | 0.00 bytes (0.0%)",
		"              Cache Dirty | 0.00 bytes (0.0%)",
	}, sectionBodyLines(text, "WiredTiger"))
	assert.Equal(t, []string{
		"       TCMalloc Allocated | 1.00 MB",
		"            TCMalloc Free | 0.00 bytes (0.0% of allocated + free)",
		"  TCMalloc Released to OS | 0.00 bytes",
	}, sectionBodyLines(text, "Memory"))

	ci = &collectedInfo{Memory: &memoryInfo{ResidentMB: pointer.ToInt64(2048)}}
	out, err = formatResults(ci, "text")
	require.NoError(t, err)
	assert.Equal(t, []string{"       Resident Set (RSS) | 2.00 GB"}, sectionBodyLines(string(out), "Memory"))
}
