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
	"fmt"
	"time"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

const minSampleTimeout = 10 * time.Second

var opcounterKeys = [...]string{"insert", "query", "update", "delete", "getmore", "command"}

type TimedStats struct {
	Min   int64
	Max   int64
	Total int64
	Avg   int64
}

type opRate struct {
	Min              float64
	Max              float64
	Avg              float64
	SinceStartPerDay float64
}

type opRates struct {
	Insert  opRate
	Query   opRate
	Update  opRate
	Delete  opRate
	GetMore opRate
	Command opRate
}

type opRow struct {
	Name string
	opRate
}

type opCounters struct {
	Insert     TimedStats
	Query      TimedStats
	Update     TimedStats
	Delete     TimedStats
	GetMore    TimedStats
	Command    TimedStats
	SampleRate time.Duration
	Elapsed    time.Duration
	Uptime     time.Duration
	Partial    string
	Rates      opRates
	ReplRates  *opRates
}

type opSampleSet struct {
	Docs      []bson.Raw
	Err       error
	Requested int
}

type opValues [len(opcounterKeys)]int64

type opTally struct {
	pairs              int
	elapsed            time.Duration
	minDelta, maxDelta opValues
	total              opValues
	minRate, maxRate   [len(opcounterKeys)]float64
}

func sampleServerStatus(ctx context.Context, client *mongo.Client, s0 bson.Raw, count int, interval time.Duration) opSampleSet {
	return sampleWith(ctx, func(ctx context.Context) (bson.Raw, error) {
		return runRaw(ctx, client, "admin", bson.D{{Key: "serverStatus", Value: 1}})
	}, s0, count, interval)
}

func sampleWith(ctx context.Context, fetch func(context.Context) (bson.Raw, error), s0 bson.Raw, count int,
	interval time.Duration,
) opSampleSet {
	set := opSampleSet{}
	if len(s0) > 0 {
		set.Docs = append(set.Docs, s0)
	}

	if count <= 0 || interval <= 0 {
		return set
	}

	set.Requested = count
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for i := 1; i <= count; i++ {
		select {
		case <-ctx.Done():
		case <-ticker.C:
		}

		if err := ctx.Err(); err != nil {
			set.Err = err

			return set
		}

		sctx, cancel := context.WithTimeout(ctx, sampleTimeout(interval))
		doc, err := fetch(sctx)
		cancel()

		if err != nil {
			log.Debugf("serverStatus sample %d of %d: %s", i, count, err)
			set.Err = err

			return set
		}

		set.Docs = append(set.Docs, doc)
	}

	return set
}

func sampleTimeout(interval time.Duration) time.Duration {
	return max(minSampleTimeout, 3*interval)
}

func summarizeRunningOps(set opSampleSet, interval time.Duration) (*opCounters, error) {
	if len(set.Docs) < 2 {
		if set.Err != nil {
			return nil, set.Err
		}

		return nil, errors.New("no serverStatus samples to compare")
	}

	var ops, repl opTally
	var end bson.Raw
	prev, skipped, lost := set.Docs[0], "", 0

	for _, cur := range set.Docs[1:] {
		dt, opsDelta, replDelta, reason := samplePairDelta(prev, cur)
		switch {
		case reason != "":
			skipped, lost = reason, lost+1
		case dt == 0:
			continue
		default:
			ops.add(opsDelta, dt)
			repl.add(replDelta, dt)
			end = cur
		}

		prev = cur
	}

	if ops.pairs == 0 {
		if set.Err != nil {
			return nil, set.Err
		}

		if lost == 0 {
			skipped = "no time elapsed between samples"
		}

		return nil, errors.Errorf("no usable sampling interval (%s)", skipped)
	}

	pairs := len(set.Docs) - 1
	oc := &opCounters{
		SampleRate: time.Duration(max(set.Requested, pairs)) * interval,
		Elapsed:    ops.elapsed,
		Uptime:     statusUptime(end),
		Rates:      ops.rates(end, "opcounters"),
	}

	for k, s := range oc.timed() {
		*s = TimedStats{Min: ops.minDelta[k], Max: ops.maxDelta[k], Total: ops.total[k], Avg: ops.total[k]}
	}

	secondary, _ := rawBool(set.Docs[0], "repl", "secondary")
	if secondary || repl.moved() {
		replRates := repl.rates(end, "opcountersRepl")
		oc.ReplRates = &replRates
	}

	switch {
	case set.Err != nil:
		reason, _, _ := classifyError(set.Err, false, "serverStatus: clusterMonitor")
		oc.Partial = fmt.Sprintf("partial: %d of %d intervals (last error: %s)",
			pairs-lost, max(set.Requested, pairs+1), reason)
	case lost > 0:
		oc.Partial = fmt.Sprintf("partial: %d of %d intervals (%s)", pairs-lost, max(set.Requested, pairs), skipped)
	}

	return oc, nil
}

func samplePairDelta(prev, cur bson.Raw) (time.Duration, opValues, opValues, string) {
	var ops, repl opValues

	dt := statusUptime(cur) - statusUptime(prev)
	if dt < 0 {
		return 0, ops, repl, "server restarted"
	}

	if !samplesFromSameProcess(prev, cur) {
		return 0, ops, repl, "host or pid changed"
	}

	before, after := opcounterValues(prev, "opcounters"), opcounterValues(cur, "opcounters")
	replBefore, replAfter := opcounterValues(prev, "opcountersRepl"), opcounterValues(cur, "opcountersRepl")

	for k := range ops {
		ops[k], repl[k] = after[k]-before[k], replAfter[k]-replBefore[k]
		if ops[k] < 0 || repl[k] < 0 {
			return 0, ops, repl, "counter went down"
		}
	}

	return dt, ops, repl, ""
}

func (t *opTally) add(delta opValues, dt time.Duration) {
	for k, d := range delta {
		rate := float64(d) / dt.Seconds()
		if t.pairs == 0 {
			t.minDelta[k], t.maxDelta[k], t.minRate[k], t.maxRate[k] = d, d, rate, rate
		}

		t.minDelta[k], t.maxDelta[k] = min(t.minDelta[k], d), max(t.maxDelta[k], d)
		t.minRate[k], t.maxRate[k] = min(t.minRate[k], rate), max(t.maxRate[k], rate)
		t.total[k] += d
	}

	t.pairs++
	t.elapsed += dt
}

func (t *opTally) moved() bool {
	for _, d := range t.total {
		if d != 0 {
			return true
		}
	}

	return false
}

func (t *opTally) rates(end bson.Raw, key string) opRates {
	var r opRates

	uptime := statusUptime(end).Seconds()
	counts := opcounterValues(end, key)

	for k, rate := range []*opRate{&r.Insert, &r.Query, &r.Update, &r.Delete, &r.GetMore, &r.Command} {
		*rate = opRate{
			Min: t.minRate[k],
			Max: t.maxRate[k],
			Avg: float64(t.total[k]) / t.elapsed.Seconds(),
		}
		if uptime > 0 {
			rate.SinceStartPerDay = float64(counts[k]) / uptime * 86400
		}
	}

	return r
}

func (oc *opCounters) timed() []*TimedStats {
	return []*TimedStats{&oc.Insert, &oc.Query, &oc.Update, &oc.Delete, &oc.GetMore, &oc.Command}
}

func (r opRates) Rows() []opRow {
	return []opRow{
		{Name: "Insert", opRate: r.Insert},
		{Name: "Query", opRate: r.Query},
		{Name: "Update", opRate: r.Update},
		{Name: "Delete", opRate: r.Delete},
		{Name: "GetMore", opRate: r.GetMore},
		{Name: "Command", opRate: r.Command},
	}
}

func (r opRates) ReplRows() []opRow {
	return []opRow{
		{Name: "Insert", opRate: r.Insert},
		{Name: "Update", opRate: r.Update},
		{Name: "Delete", opRate: r.Delete},
		{Name: "Command", opRate: r.Command},
	}
}

func opcounterValues(doc bson.Raw, key string) opValues {
	var counts opValues

	section, _ := rawDoc(doc, key)
	for k, name := range opcounterKeys {
		counts[k], _ = rawInt64(section, name)
	}

	return counts
}

func statusUptime(doc bson.Raw) time.Duration {
	ms, _ := rawInt64(doc, "uptimeMillis")

	return time.Duration(ms) * time.Millisecond
}

func samplesFromSameProcess(a, b bson.Raw) bool {
	hostA, _ := rawString(a, "host")
	hostB, _ := rawString(b, "host")
	pidA, _ := rawInt64(a, "pid")
	pidB, _ := rawInt64(b, "pid")

	return hostA == hostB && pidA == pidB
}
