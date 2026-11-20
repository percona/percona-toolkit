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
	"math"
	"time"

	"go.mongodb.org/mongo-driver/bson"
)

const wtCounterCount = 8

var tcmallocFreeLists = []string{
	"central_cache_free_bytes", "transfer_cache_free_bytes", "thread_cache_free_bytes",
	"central_cache_free", "transfer_cache_free", "sharded_transfer_cache_free", "thread_cache_free", "cpu_free",
}

type wtCounter struct {
	Total  int64
	PerSec float64
}

type wiredTigerInfo struct {
	Engine                  string
	CacheMaxBytes           int64
	CacheUsedBytes          int64
	CacheUsedPct            float64
	CacheFreeBytes          int64
	CacheFreePct            float64
	CacheDirtyBytes         int64
	CacheDirtyPct           float64
	CacheUpdatesBytes       *int64
	CacheUpdatesPct         float64
	Window                  time.Duration
	PagesReadIntoCache      wtCounter
	BytesReadIntoCache      wtCounter
	PagesWrittenFromCache   wtCounter
	BytesWrittenFromCache   wtCounter
	UnmodifiedPagesEvicted  wtCounter
	ModifiedPagesEvicted    wtCounter
	AppThreadEvictions      wtCounter
	AppThreadCacheWaitUsecs wtCounter
}

type tcmallocInfo struct {
	AllocatedBytes    int64
	HeapSizeBytes     int64
	PageheapFreeBytes int64
	CacheFreeBytes    int64
	UnmappedBytes     int64
	FreePct           float64
	PerCPUCaches      *bool
}

type memoryInfo struct {
	ResidentMB *int64
	TCMalloc   *tcmallocInfo
}

func buildWiredTiger(snap *snapshot, set opSampleSet, g *gaps) *wiredTigerInfo {
	engine, _ := rawString(snap.ServerStatus, "storageEngine", "name")
	if engine != "wiredTiger" && engine != "inMemory" {
		return nil
	}

	stats, _ := rawDoc(snap.ServerStatus, engine)
	cacheMax, ok := rawInt64(stats, "cache", "maximum bytes configured")
	if !ok {
		g.note("WiredTiger", "WiredTiger",
			"serverStatus returned no "+engine+" statistics (the server omits them while busy)", false)

		return nil
	}

	used, _ := rawInt64(stats, "cache", "bytes currently in the cache")
	dirty, _ := rawInt64(stats, "cache", "tracked dirty bytes in the cache")
	free := max(cacheMax-used, 0)

	wt := &wiredTigerInfo{
		Engine:          engine,
		CacheMaxBytes:   cacheMax,
		CacheUsedBytes:  used,
		CacheUsedPct:    sharePct(used, cacheMax),
		CacheFreeBytes:  free,
		CacheFreePct:    sharePct(free, cacheMax),
		CacheDirtyBytes: dirty,
		CacheDirtyPct:   sharePct(dirty, cacheMax),
	}

	if updates, ok := rawInt64(stats, "cache", "bytes allocated for updates"); ok {
		wt.CacheUpdatesBytes = &updates
		wt.CacheUpdatesPct = sharePct(updates, cacheMax)
	}

	counters := wt.counters()
	for i, v := range wtCounterValues(stats) {
		counters[i].Total = v
	}

	if window, rates, ok := wtRates(set, engine); ok {
		wt.Window = window
		for i, r := range rates {
			counters[i].PerSec = r
		}
	}

	return wt
}

func wtRates(set opSampleSet, engine string) (time.Duration, [wtCounterCount]float64, bool) {
	var rates [wtCounterCount]float64

	if len(set.Docs) < 2 {
		return 0, rates, false
	}

	first, last := set.Docs[0], set.Docs[len(set.Docs)-1]
	window := statusUptime(last) - statusUptime(first)
	if window < time.Second || !samplesFromSameProcess(first, last) {
		return 0, rates, false
	}

	before, okBefore := rawDoc(first, engine)
	after, okAfter := rawDoc(last, engine)
	if !okBefore || !okAfter {
		return 0, rates, false
	}

	from, to := wtCounterValues(before), wtCounterValues(after)
	for i := range rates {
		delta := to[i] - from[i]
		if delta < 0 {
			return 0, rates, false
		}

		rates[i] = float64(delta) / window.Seconds()
	}

	return window, rates, true
}

func wtCounterValues(stats bson.Raw) [wtCounterCount]int64 {
	cache, _ := rawDoc(stats, "cache")
	yield, _ := rawDoc(stats, "thread-yield")

	value := func(doc bson.Raw, key string) int64 {
		v, _ := rawInt64(doc, key)

		return v
	}

	return [wtCounterCount]int64{
		value(cache, "pages read into cache"),
		value(cache, "bytes read into cache"),
		value(cache, "pages written from cache"),
		value(cache, "bytes written from cache"),
		value(cache, "unmodified pages evicted"),
		value(cache, "modified pages evicted"),
		value(cache, "pages evicted by application threads") +
			value(cache, "page evict attempts by application threads"),
		value(yield, "application thread time waiting for cache (usecs)"),
	}
}

func (w *wiredTigerInfo) counters() [wtCounterCount]*wtCounter {
	return [wtCounterCount]*wtCounter{
		&w.PagesReadIntoCache, &w.BytesReadIntoCache, &w.PagesWrittenFromCache, &w.BytesWrittenFromCache,
		&w.UnmodifiedPagesEvicted, &w.ModifiedPagesEvicted, &w.AppThreadEvictions, &w.AppThreadCacheWaitUsecs,
	}
}

func (c wtCounter) PerSecBytes() int64 {
	return int64(math.Round(c.PerSec))
}

func (c wtCounter) PerSecMillis() float64 {
	return c.PerSec / 1000
}

func buildMemory(snap *snapshot) *memoryInfo {
	m := &memoryInfo{TCMalloc: buildTCMalloc(snap.ServerStatus)}

	if supported, ok := rawBool(snap.ServerStatus, "mem", "supported"); !ok || supported {
		if resident, ok := rawInt64(snap.ServerStatus, "mem", "resident"); ok {
			m.ResidentMB = &resident
		}
	}

	if m.ResidentMB == nil && m.TCMalloc == nil {
		return nil
	}

	return m
}

func buildTCMalloc(serverStatus bson.Raw) *tcmallocInfo {
	tc, _ := rawDoc(serverStatus, "tcmalloc")

	allocated, ok := rawInt64(tc, "generic", "current_allocated_bytes")
	if !ok {
		return nil
	}

	t := &tcmallocInfo{AllocatedBytes: allocated}
	t.HeapSizeBytes, _ = rawInt64(tc, "generic", "heap_size")
	t.PageheapFreeBytes, _ = rawInt64(tc, "tcmalloc", "pageheap_free_bytes")
	t.UnmappedBytes, _ = rawInt64(tc, "tcmalloc", "pageheap_unmapped_bytes")

	for _, key := range tcmallocFreeLists {
		v, _ := rawInt64(tc, "tcmalloc", key)
		t.CacheFreeBytes += v
	}

	if perCPU, ok := rawBool(tc, "usingPerCPUCaches"); ok {
		t.PerCPUCaches = &perCPU
	}

	t.FreePct = sharePct(t.FreeBytes(), t.AllocatedBytes+t.FreeBytes())

	return t
}

func (t *tcmallocInfo) FreeBytes() int64 {
	return t.PageheapFreeBytes + t.CacheFreeBytes
}

func (t *tcmallocInfo) PerCPU() string {
	switch {
	case t.PerCPUCaches == nil:
		return ""
	case *t.PerCPUCaches:
		return "yes"
	}

	return "no"
}

func (m *memoryInfo) ResidentBytes() int64 {
	return *m.ResidentMB << 20
}

func sharePct(part, whole int64) float64 {
	if whole <= 0 {
		return 0
	}

	return 100 * float64(part) / float64(whole)
}
