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
	"encoding/json"
	"math"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
)

type statusPoint struct {
	Host      string
	Pid       int64
	UptimeMs  int64
	Ops       [6]int64
	Repl      [6]int64
	Secondary bool
}

func cmdPoint(uptimeMs, command int64) statusPoint {
	return statusPoint{Host: "db:27017", Pid: 7, UptimeMs: uptimeMs, Ops: [6]int64{5: command}}
}

func (p statusPoint) raw(t *testing.T) bson.Raw {
	t.Helper()

	counters := func(v [6]int64) bson.D {
		return bson.D{
			{Key: "insert", Value: v[0]},
			{Key: "query", Value: v[1]},
			{Key: "update", Value: v[2]},
			{Key: "delete", Value: v[3]},
			{Key: "getmore", Value: v[4]},
			{Key: "command", Value: v[5]},
		}
	}

	return mustRaw(t, bson.D{
		{Key: "host", Value: p.Host},
		{Key: "pid", Value: p.Pid},
		{Key: "uptimeMillis", Value: p.UptimeMs},
		{Key: "opcounters", Value: counters(p.Ops)},
		{Key: "opcountersRepl", Value: counters(p.Repl)},
		{Key: "repl", Value: bson.D{{Key: "secondary", Value: p.Secondary}}},
	})
}

func pointSet(t *testing.T, points ...statusPoint) opSampleSet {
	t.Helper()

	set := opSampleSet{}
	for _, p := range points {
		set.Docs = append(set.Docs, p.raw(t))
	}

	return set
}

func TestSummarizeRunningOpsStretchedInterval(t *testing.T) {
	set := pointSet(t, cmdPoint(1000, 100), cmdPoint(2000, 200), cmdPoint(4000, 400))

	oc, err := summarizeRunningOps(set, time.Second)
	require.NoError(t, err)

	assert.Equal(t, opRate{Min: 100, Max: 100, Avg: 100, SinceStartPerDay: 8640000}, oc.Rates.Command)
	assert.Equal(t, TimedStats{Min: 100, Max: 200, Total: 300, Avg: 300}, oc.Command)
	assert.Equal(t, 3*time.Second, oc.Elapsed)
	assert.Equal(t, 4*time.Second, oc.Uptime)
	assert.Equal(t, 2*time.Second, oc.SampleRate)
	assert.Empty(t, oc.Partial)
}

func TestSummarizeRunningOpsSkippedPairs(t *testing.T) {
	otherHost := cmdPoint(3000, 1000)
	otherHost.Host = "other:27017"
	otherPid := cmdPoint(3000, 1000)
	otherPid.Pid = 8
	otherPidSameUptime := cmdPoint(2000, 1000)
	otherPidSameUptime.Pid = 8

	tests := []struct {
		name    string
		points  []statusPoint
		rate    opRate
		stats   TimedStats
		elapsed time.Duration
		uptime  time.Duration
		partial string
	}{
		{
			name:    "restart",
			points:  []statusPoint{cmdPoint(10000, 1000), cmdPoint(11000, 1100), cmdPoint(500, 1200), cmdPoint(1500, 1250)},
			rate:    opRate{Min: 50, Max: 100, Avg: 75, SinceStartPerDay: 1250 / 1.5 * 86400},
			stats:   TimedStats{Min: 50, Max: 100, Total: 150, Avg: 150},
			elapsed: 2 * time.Second,
			uptime:  1500 * time.Millisecond,
			partial: "partial: 2 of 3 intervals (server restarted)",
		},
		{
			name:    "host change",
			points:  []statusPoint{cmdPoint(1000, 10), cmdPoint(2000, 20), otherHost},
			rate:    opRate{Min: 10, Max: 10, Avg: 10, SinceStartPerDay: 20 / 2.0 * 86400},
			stats:   TimedStats{Min: 10, Max: 10, Total: 10, Avg: 10},
			elapsed: time.Second,
			uptime:  2 * time.Second,
			partial: "partial: 1 of 2 intervals (host or pid changed)",
		},
		{
			name:    "pid change",
			points:  []statusPoint{cmdPoint(1000, 10), cmdPoint(2000, 20), otherPid},
			rate:    opRate{Min: 10, Max: 10, Avg: 10, SinceStartPerDay: 20 / 2.0 * 86400},
			stats:   TimedStats{Min: 10, Max: 10, Total: 10, Avg: 10},
			elapsed: time.Second,
			uptime:  2 * time.Second,
			partial: "partial: 1 of 2 intervals (host or pid changed)",
		},
		{
			name:    "counter went down",
			points:  []statusPoint{cmdPoint(1000, 100), cmdPoint(2000, 50), cmdPoint(4000, 110)},
			rate:    opRate{Min: 30, Max: 30, Avg: 30, SinceStartPerDay: 110 / 4.0 * 86400},
			stats:   TimedStats{Min: 60, Max: 60, Total: 60, Avg: 60},
			elapsed: 2 * time.Second,
			uptime:  4 * time.Second,
			partial: "partial: 1 of 2 intervals (counter went down)",
		},
		{
			name:    "same uptime at start",
			points:  []statusPoint{cmdPoint(1000, 10), cmdPoint(1000, 11), cmdPoint(2000, 20)},
			rate:    opRate{Min: 10, Max: 10, Avg: 10, SinceStartPerDay: 20 / 2.0 * 86400},
			stats:   TimedStats{Min: 10, Max: 10, Total: 10, Avg: 10},
			elapsed: time.Second,
			uptime:  2 * time.Second,
		},
		{
			name:    "same uptime in the middle",
			points:  []statusPoint{cmdPoint(1000, 10), cmdPoint(2000, 20), cmdPoint(2000, 21), cmdPoint(3000, 40)},
			rate:    opRate{Min: 10, Max: 20, Avg: 15, SinceStartPerDay: 40 / 3.0 * 86400},
			stats:   TimedStats{Min: 10, Max: 20, Total: 30, Avg: 30},
			elapsed: 2 * time.Second,
			uptime:  3 * time.Second,
		},
		{
			name:    "same uptime at the end",
			points:  []statusPoint{cmdPoint(1000, 10), cmdPoint(2000, 20), cmdPoint(2000, 21)},
			rate:    opRate{Min: 10, Max: 10, Avg: 10, SinceStartPerDay: 20 / 2.0 * 86400},
			stats:   TimedStats{Min: 10, Max: 10, Total: 10, Avg: 10},
			elapsed: time.Second,
			uptime:  2 * time.Second,
		},
		{
			name:    "pid change at the same uptime",
			points:  []statusPoint{cmdPoint(1000, 10), cmdPoint(2000, 20), otherPidSameUptime},
			rate:    opRate{Min: 10, Max: 10, Avg: 10, SinceStartPerDay: 20 / 2.0 * 86400},
			stats:   TimedStats{Min: 10, Max: 10, Total: 10, Avg: 10},
			elapsed: time.Second,
			uptime:  2 * time.Second,
			partial: "partial: 1 of 2 intervals (host or pid changed)",
		},
		{
			name:    "counter went down at the same uptime",
			points:  []statusPoint{cmdPoint(1000, 100), cmdPoint(1000, 50), cmdPoint(2000, 60)},
			rate:    opRate{Min: 10, Max: 10, Avg: 10, SinceStartPerDay: 60 / 2.0 * 86400},
			stats:   TimedStats{Min: 10, Max: 10, Total: 10, Avg: 10},
			elapsed: time.Second,
			uptime:  2 * time.Second,
			partial: "partial: 1 of 2 intervals (counter went down)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			oc, err := summarizeRunningOps(pointSet(t, tt.points...), time.Second)
			require.NoError(t, err)

			assert.InDelta(t, tt.rate.Min, oc.Rates.Command.Min, 1e-9)
			assert.InDelta(t, tt.rate.Max, oc.Rates.Command.Max, 1e-9)
			assert.InDelta(t, tt.rate.Avg, oc.Rates.Command.Avg, 1e-9)
			assert.InDelta(t, tt.rate.SinceStartPerDay, oc.Rates.Command.SinceStartPerDay, 1e-6)
			assert.Equal(t, tt.stats, oc.Command)
			assert.Equal(t, tt.elapsed, oc.Elapsed)
			assert.Equal(t, tt.uptime, oc.Uptime)
			assert.Equal(t, tt.partial, oc.Partial)
		})
	}
}

func TestSummarizeRunningOpsNoUsablePair(t *testing.T) {
	_, err := summarizeRunningOps(opSampleSet{}, time.Second)
	require.Error(t, err)

	oc, err := summarizeRunningOps(pointSet(t, cmdPoint(1000, 1)), time.Second)
	require.Error(t, err)
	assert.Nil(t, oc)

	oc, err = summarizeRunningOps(pointSet(t, cmdPoint(2000, 10), cmdPoint(1000, 20)), time.Second)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "server restarted")
	assert.Nil(t, oc)

	oc, err = summarizeRunningOps(pointSet(t, cmdPoint(1000, 10), cmdPoint(1000, 11), cmdPoint(1000, 12)), time.Second)
	require.Error(t, err)
	assert.Equal(t, "no usable sampling interval (no time elapsed between samples)", err.Error())
	assert.Nil(t, oc)

	set := pointSet(t, cmdPoint(1000, 1))
	set.Err = errors.Wrap(context.DeadlineExceeded, "serverStatus")
	oc, err = summarizeRunningOps(set, time.Second)
	require.ErrorIs(t, err, context.DeadlineExceeded)
	assert.Nil(t, oc)
	reason, _, _ := classifyError(err, false, "serverStatus: clusterMonitor")
	assert.Equal(t, "timed out", reason)
}

func TestSummarizeRunningOpsPartial(t *testing.T) {
	set := pointSet(t, cmdPoint(1000, 10), cmdPoint(2000, 20), cmdPoint(3000, 40))
	set.Err = errors.New("connection reset by peer")

	oc, err := summarizeRunningOps(set, time.Second)
	require.NoError(t, err)

	assert.Equal(t, "partial: 2 of 3 intervals (last error: connection reset by peer)", oc.Partial)
	assert.Equal(t, opRate{Min: 10, Max: 20, Avg: 15, SinceStartPerDay: 40 / 3.0 * 86400}, oc.Rates.Command)
	assert.Equal(t, 2*time.Second, oc.Elapsed)

	set = pointSet(t, cmdPoint(1000, 10), cmdPoint(2000, 20))
	set.Err = errors.Wrap(context.DeadlineExceeded, "server selection error")
	oc, err = summarizeRunningOps(set, time.Second)
	require.NoError(t, err)
	assert.Equal(t, "partial: 1 of 2 intervals (last error: timed out)", oc.Partial)

	set = pointSet(t, cmdPoint(1000, 10), cmdPoint(2000, 20), cmdPoint(3000, 40))
	set.Err, set.Requested = errors.New("connection reset by peer"), 5
	oc, err = summarizeRunningOps(set, time.Second)
	require.NoError(t, err)
	assert.Equal(t, "partial: 2 of 5 intervals (last error: connection reset by peer)", oc.Partial)
	assert.Equal(t, 5*time.Second, oc.SampleRate)
	assert.Equal(t, 2*time.Second, oc.Elapsed)

	set = pointSet(t, cmdPoint(1000, 10), cmdPoint(1000, 11), cmdPoint(2000, 20))
	set.Err, set.Requested = errors.New("connection reset by peer"), 5
	oc, err = summarizeRunningOps(set, time.Second)
	require.NoError(t, err)
	assert.Equal(t, "partial: 2 of 5 intervals (last error: connection reset by peer)", oc.Partial)
	assert.Equal(t, opRate{Min: 10, Max: 10, Avg: 10, SinceStartPerDay: 20 / 2.0 * 86400}, oc.Rates.Command)
	assert.Equal(t, time.Second, oc.Elapsed)
}

func TestSummarizeRunningOpsNoNaN(t *testing.T) {
	set := pointSet(t, cmdPoint(1000, 10), cmdPoint(1001, math.MaxInt64/2), cmdPoint(0, 5))

	oc, err := summarizeRunningOps(set, time.Millisecond)
	require.NoError(t, err)

	assert.Equal(t, 1001*time.Millisecond, oc.Uptime)
	assert.Equal(t, "partial: 1 of 2 intervals (server restarted)", oc.Partial)

	_, err = json.Marshal(oc)
	require.NoError(t, err)

	for _, r := range []opRate{oc.Rates.Insert, oc.Rates.Query, oc.Rates.Command} {
		for _, v := range []float64{r.Min, r.Max, r.Avg, r.SinceStartPerDay} {
			assert.False(t, math.IsNaN(v) || math.IsInf(v, 0), "%v", v)
		}
	}

	oc, err = summarizeRunningOps(pointSet(t, cmdPoint(-1000, 0), cmdPoint(0, 10)), time.Second)
	require.NoError(t, err)
	assert.Equal(t, opRate{Min: 10, Max: 10, Avg: 10}, oc.Rates.Command)
	_, err = json.Marshal(oc)
	require.NoError(t, err)
}

func TestSampleServerStatusBaseline(t *testing.T) {
	s0 := cmdPoint(1000, 1).raw(t)
	docs := []bson.Raw{cmdPoint(2000, 2).raw(t), cmdPoint(3000, 3).raw(t)}

	calls := 0
	fetch := func(context.Context) (bson.Raw, error) {
		calls++
		if calls > len(docs) {
			t.Fatalf("unexpected sample %d", calls)
		}

		return docs[calls-1], nil
	}

	interval := 200 * time.Millisecond
	start := time.Now()
	set := sampleWith(context.Background(), fetch, s0, len(docs), interval)
	elapsed := time.Since(start)

	require.NoError(t, set.Err)
	assert.Equal(t, len(docs), calls)
	assert.Equal(t, []bson.Raw{s0, docs[0], docs[1]}, set.Docs)
	assert.Equal(t, len(docs), set.Requested)
	assert.GreaterOrEqual(t, elapsed, 2*interval-10*time.Millisecond)
	assert.Less(t, elapsed, 3*interval-40*time.Millisecond)

	for _, count := range []int{0, -1} {
		set = sampleWith(context.Background(), fetch, s0, count, interval)
		assert.Equal(t, opSampleSet{Docs: []bson.Raw{s0}}, set)
	}
	set = sampleWith(context.Background(), fetch, s0, 3, 0)
	assert.Equal(t, opSampleSet{Docs: []bson.Raw{s0}}, set)
	assert.Equal(t, len(docs), calls)

	calls = 0
	set = sampleWith(context.Background(), fetch, nil, len(docs), time.Millisecond)
	require.NoError(t, set.Err)
	assert.Equal(t, docs, set.Docs)
}

func TestSampleServerStatusStopsAtFirstError(t *testing.T) {
	s0 := cmdPoint(1000, 1).raw(t)
	d1 := cmdPoint(2000, 2).raw(t)
	boom := errors.New("boom")

	calls := 0
	fetch := func(context.Context) (bson.Raw, error) {
		calls++
		switch calls {
		case 1:
			return d1, nil
		case 2:
			return nil, boom
		}
		t.Fatalf("sampling continued after an error")

		return nil, nil
	}

	set := sampleWith(context.Background(), fetch, s0, 5, time.Millisecond)

	assert.Equal(t, []bson.Raw{s0, d1}, set.Docs)
	require.ErrorIs(t, set.Err, boom)
	assert.Equal(t, 2, calls)
	assert.Equal(t, 5, set.Requested)

	oc, err := summarizeRunningOps(set, time.Second)
	require.NoError(t, err)
	assert.Equal(t, "partial: 1 of 5 intervals (last error: boom)", oc.Partial)
}

func TestSampleServerStatusSampleDeadline(t *testing.T) {
	doc := cmdPoint(2000, 2).raw(t)

	var deadlines, calledAt []time.Time
	fetch := func(ctx context.Context) (bson.Raw, error) {
		d, ok := ctx.Deadline()
		require.True(t, ok)
		deadlines = append(deadlines, d)
		calledAt = append(calledAt, time.Now())

		return doc, nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()

	set := sampleWith(ctx, fetch, doc, 2, time.Millisecond)
	require.NoError(t, set.Err)
	require.Len(t, deadlines, 2)
	for i := range deadlines {
		assert.WithinDuration(t, calledAt[i].Add(10*time.Second), deadlines[i], 100*time.Millisecond)
	}

	short, cancelShort := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancelShort()

	deadlines, calledAt = nil, nil
	set = sampleWith(short, fetch, doc, 1, time.Millisecond)
	require.NoError(t, set.Err)
	require.Len(t, deadlines, 1)
	parent, _ := short.Deadline()
	assert.Equal(t, parent, deadlines[0])

	assert.Equal(t, 10*time.Second, sampleTimeout(time.Second))
	assert.Equal(t, 15*time.Second, sampleTimeout(5*time.Second))
}

func TestSampleServerStatusParentDeadline(t *testing.T) {
	s0 := cmdPoint(1000, 1).raw(t)
	fetch := func(context.Context) (bson.Raw, error) {
		return cmdPoint(2000, 2).raw(t), nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()

	start := time.Now()
	set := sampleWith(ctx, fetch, s0, 100, 20*time.Millisecond)

	require.ErrorIs(t, set.Err, context.DeadlineExceeded)
	assert.Less(t, time.Since(start), time.Second)
	require.NotEmpty(t, set.Docs)
	assert.Equal(t, s0, set.Docs[0])
	assert.Less(t, len(set.Docs), 10)
}

func TestSampleServerStatusUnreachable(t *testing.T) {
	client, _ := unreachableClient(t, closedAddr(t), 100*time.Millisecond)
	s0 := cmdPoint(1000, 1).raw(t)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	start := time.Now()
	set := sampleServerStatus(ctx, client, s0, 3, 10*time.Millisecond)

	assert.Equal(t, []bson.Raw{s0}, set.Docs)
	require.Error(t, set.Err)
	assert.Less(t, time.Since(start), 2*time.Second)
}
