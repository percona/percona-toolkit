// This program is copyright 2026 Percona LLC and/or its affiliates.
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

package stats

import (
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"

	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

func findDoc(customerID int, millis int, ts time.Time, planSummary, appName, client, user string) proto.SystemProfile {
	return proto.SystemProfile{
		Ns: "shop.orders",
		Op: "query",
		Command: bson.D{
			{Key: "find", Value: "orders"},
			{Key: "filter", Value: bson.D{{Key: "customerId", Value: customerID}}},
		},
		Millis:      millis,
		Ts:          ts,
		PlanSummary: planSummary,
		AppName:     appName,
		Client:      client,
		User:        user,
	}
}

func TestWorstSample(t *testing.T) {
	t0 := time.Date(2026, 11, 3, 10, 0, 0, 0, time.UTC)
	docs := []proto.SystemProfile{
		findDoc(1, 10, t0, "COLLSCAN", "orders-api", "10.0.0.1", "app@admin"),
		findDoc(2, 50, t0.Add(time.Second), "IXSCAN { customerId: 1 }", "reporting", "10.0.0.2", "report@admin"),
		findDoc(3, 20, t0.Add(2*time.Second), "COLLSCAN", "orders-api", "10.0.0.1", "app@admin"),
		// same execution time as the slowest one: the last one processed wins, like pt-query-digest
		findDoc(4, 50, t0.Add(3*time.Second), "COLLSCAN", "orders-api", "10.0.0.3", "app@admin"),
		findDoc(5, 5, t0.Add(4*time.Second), "COLLSCAN", "", "", ""),
	}

	s := New(fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters()))
	for _, doc := range docs {
		require.NoError(t, s.Add(doc))
	}

	queries := s.Queries()
	require.Len(t, queries, 1)
	q := queries[0]

	assert.Equal(t, 5, q.Count)
	assert.Equal(t, `{"ns":"shop.orders","op":"query","command":{"find":"orders","filter":{"customerId":{"$numberInt":"4"}}}}`, q.Query)
	assert.Equal(t, t0.Add(3*time.Second), q.SampleTs)
	assert.Equal(t, 50.0, q.SampleQueryTime)
	assert.Equal(t, "COLLSCAN", q.PlanSummary)
	assert.Equal(t, "orders-api", q.AppName)
	assert.Equal(t, "10.0.0.3", q.Client)
	assert.Equal(t, "app", q.User)
	assert.Equal(t, t0, q.FirstSeen)
	assert.Equal(t, t0.Add(4*time.Second), q.LastSeen)

	assert.Equal(t, 4, q.CollScanCount)
	assert.Equal(t, map[string]int{"COLLSCAN": 4, "IXSCAN { customerId: 1 }": 1}, q.PlanSummaries)
	assert.Equal(t, map[string]int{"orders-api": 3, "reporting": 1}, q.AppNames)
	assert.Equal(t, map[string]int{"10.0.0.1": 2, "10.0.0.2": 1, "10.0.0.3": 1}, q.Clients)
	assert.Equal(t, map[string]int{"app": 3, "report": 1}, q.Users)

	qs := queries.CalcQueriesStats(1)
	require.Len(t, qs, 1)
	assert.Equal(t, []ValueCount{{"COLLSCAN", 4}, {"IXSCAN { customerId: 1 }", 1}}, qs[0].PlanSummaries)
	assert.Equal(t, []ValueCount{{"10.0.0.1", 2}, {"10.0.0.2", 1}, {"10.0.0.3", 1}}, qs[0].Clients)
	assert.Equal(t, t0.Add(3*time.Second), qs[0].SampleTs)
	assert.Equal(t, 50.0, qs[0].SampleQueryTime)
}

// A query without docsExamined (e.g. an insert) must not turn the totals into NaN,
// leaving the percentages of all the queries at 0
func TestPercentagesWithMissingMetrics(t *testing.T) {
	s := New(fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters()))
	find := findDoc(1, 10, time.Now(), "COLLSCAN", "", "", "")
	find.DocsExamined = 300
	find.KeysExamined = 30
	require.NoError(t, s.Add(find))
	find = findDoc(2, 10, time.Now(), "COLLSCAN", "", "", "")
	find.Command = bson.D{{Key: "find", Value: "orders"}, {Key: "filter", Value: bson.D{{Key: "status", Value: "x"}}}}
	find.DocsExamined = 100
	find.KeysExamined = 10
	require.NoError(t, s.Add(find))
	require.NoError(t, s.Add(proto.SystemProfile{
		Ns: "shop.orders", Op: "insert", Millis: 5,
		Command: bson.D{{Key: "insert", Value: "orders"}},
	}))

	queries := s.Queries()
	for _, q := range queries.CalcQueriesStats(1) {
		switch q.Fingerprint {
		case "FIND orders customerId":
			assert.Equal(t, 75.0, q.DocsExamined.Pct)
			assert.Equal(t, 75.0, q.KeysExamined.Pct)
		case "FIND orders status":
			assert.Equal(t, 25.0, q.DocsExamined.Pct)
			assert.Equal(t, 25.0, q.KeysExamined.Pct)
		case "INSERT orders":
			assert.Equal(t, 0.0, q.DocsExamined.Pct)
		default:
			t.Errorf("unexpected fingerprint %q", q.Fingerprint)
		}
	}
	assert.Equal(t, 100.0, queries.CalcTotalQueriesStats(1).DocsExamined.Pct)
}

func TestSortValueCounts(t *testing.T) {
	assert.Nil(t, sortValueCounts(nil))
	assert.Equal(t,
		[]ValueCount{{"c", 3}, {"a", 1}, {"b", 1}},
		sortValueCounts(map[string]int{"b": 1, "c": 3, "a": 1}),
	)
}

// Queries returns a snapshot: later calls to Add must not change it (the profiler flushes
// stats periodically while documents are still being added).
func TestQueriesSnapshot(t *testing.T) {
	t0 := time.Date(2026, 11, 3, 10, 0, 0, 0, time.UTC)
	s := New(fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters()))
	require.NoError(t, s.Add(findDoc(1, 10, t0, "COLLSCAN", "orders-api", "10.0.0.1", "app@admin")))

	snapshot := s.Queries()
	require.NoError(t, s.Add(findDoc(2, 20, t0, "IXSCAN { customerId: 1 }", "reporting", "10.0.0.2", "report@admin")))

	require.Len(t, snapshot, 1)
	assert.Equal(t, 1, snapshot[0].Count)
	assert.Equal(t, map[string]int{"COLLSCAN": 1}, snapshot[0].PlanSummaries)
	assert.Equal(t, map[string]int{"orders-api": 1}, snapshot[0].AppNames)
	assert.Equal(t, map[string]int{"10.0.0.1": 1}, snapshot[0].Clients)
	assert.Equal(t, map[string]int{"app": 1}, snapshot[0].Users)
}

func TestQueriesConcurrentAdd(t *testing.T) {
	t0 := time.Date(2026, 11, 3, 10, 0, 0, 0, time.UTC)
	s := New(fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters()))
	require.NoError(t, s.Add(findDoc(1, 10, t0, "COLLSCAN", "orders-api", "10.0.0.1", "app@admin")))

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 1000; i++ {
			_ = s.Add(findDoc(i, i, t0, fmt.Sprintf("plan%d", i), fmt.Sprintf("app%d", i), "10.0.0.1", "app@admin"))
		}
	}()
	for i := 0; i < 100; i++ {
		_ = s.Queries().CalcQueriesStats(1)
	}
	<-done
}
