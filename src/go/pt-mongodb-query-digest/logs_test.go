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

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/pborman/getopt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
)

func sampleLog(t *testing.T, version string) string {
	root, err := tutil.RootPath()
	require.NoError(t, err)
	return filepath.Join(root, "src", "go", "tests", "logs", "mongod-"+version+".log")
}

func parseArgs(t *testing.T, args ...string) (*cliOptions, error) {
	getopt.Reset()
	os.Args = append([]string{toolname}, args...)
	return getOptions()
}

func TestParseArgsLogFiles(t *testing.T) {
	log42, log60 := sampleLog(t, "4.2"), sampleLog(t, "6.0")

	opts, err := parseArgs(t, log42, "--since=2026-11-04T11:33:00Z", log60, "--until", "2026-11-04 12:00:00",
		"--show-all=client,app-name", "--database=shop")
	require.NoError(t, err)
	assert.Equal(t, []string{log42, log60}, opts.LogFiles)
	assert.Equal(t, "mongodb://"+DEFAULT_HOST, opts.Host)
	assert.Equal(t, "shop", opts.Database)
	assert.Equal(t, []string{"client", "app-name"}, opts.ShowAll)
	assert.True(t, opts.Since.Equal(time.Date(2026, 11, 4, 11, 33, 0, 0, time.UTC)))
	assert.True(t, opts.Until.Equal(time.Date(2026, 11, 4, 12, 0, 0, 0, time.Local)))

	opts, err = parseArgs(t, "-")
	require.NoError(t, err)
	assert.Equal(t, []string{"-"}, opts.LogFiles)

	opts, err = parseArgs(t, "localhost:27018")
	require.NoError(t, err)
	assert.Nil(t, opts.LogFiles)
	assert.Equal(t, "mongodb://localhost:27018", opts.Host)

	// looks like a log file, so don't try to connect to a host called like that
	opts, err = parseArgs(t, "/does/not/exist/mongod.log")
	require.NoError(t, err)
	assert.Equal(t, []string{"/does/not/exist/mongod.log"}, opts.LogFiles)

	_, err = parseArgs(t, "localhost:27018", log42)
	assert.Error(t, err)

	_, err = parseArgs(t, log42, "--show-all=foo")
	assert.Error(t, err)

	_, err = parseArgs(t, log42, "--since=yesterday")
	assert.Error(t, err)

	_, err = parseArgs(t, log42, "--since=2026-11-04", "--until=2026-11-03")
	assert.Error(t, err)
}

func TestParseTimeOption(t *testing.T) {
	now := time.Date(2026, 11, 4, 12, 0, 0, 0, time.UTC)
	tests := map[string]time.Time{
		"30s":                         now.Add(-30 * time.Second),
		"15m":                         now.Add(-15 * time.Minute),
		"12h":                         now.Add(-12 * time.Hour),
		"7d":                          now.Add(-7 * 24 * time.Hour),
		"2026-11-03T10:00:00Z":        time.Date(2026, 11, 3, 10, 0, 0, 0, time.UTC),
		"2026-11-03T10:00:00.5-03:00": time.Date(2026, 11, 3, 13, 0, 0, 500000000, time.UTC),
		"2026-11-03T10:00:00":         time.Date(2026, 11, 3, 10, 0, 0, 0, time.Local),
		"2026-11-03 10:00:00":         time.Date(2026, 11, 3, 10, 0, 0, 0, time.Local),
		"2026-11-03":                  time.Date(2026, 11, 3, 0, 0, 0, 0, time.Local),
	}
	for in, want := range tests {
		got, err := parseTimeOption(in, now)
		require.NoError(t, err, in)
		assert.True(t, want.Equal(got), "%s: got %s, want %s", in, got, want)
	}
	for _, in := range []string{"", "1w", "today", "2026-13-01"} {
		_, err := parseTimeOption(in, now)
		assert.Error(t, err, in)
	}
}

func TestFormatStringList(t *testing.T) {
	vc := func(vals ...interface{}) []stats.ValueCount {
		r := []stats.ValueCount{}
		for i := 0; i < len(vals); i += 2 {
			r = append(r, stats.ValueCount{Value: vals[i].(string), Count: vals[i+1].(int)})
		}
		return r
	}

	assert.Equal(t, "orders-api", formatStringList(vc("orders-api", 10), 10, false))
	assert.Equal(t, "orders-api (8/80%), reporting (2/20%)", formatStringList(vc("orders-api", 8, "reporting", 2), 10, false))
	assert.Equal(t, "10.0.4.17 (4/40%), 10.0.4.18 (3/30%)... 2 more",
		formatStringList(vc("10.0.4.17", 4, "10.0.4.18", 3, "10.0.4.22", 2, "10.0.4.23", 1), 10, false))
	assert.Equal(t, "10.0.4.17 (4/40%), 10.0.4.18 (3/30%), 10.0.4.22 (2/20%), 10.0.4.23 (1/10%)",
		formatStringList(vc("10.0.4.17", 4, "10.0.4.18", 3, "10.0.4.22", 2, "10.0.4.23", 1), 10, true))

	// values are never cut
	long := "IXSCAN { flight_id: 1, equipment.plane_type: 1, status: 1, departure: -1 }"
	assert.Equal(t, long, formatStringList(vc(long, 1), 1, false))
	assert.Equal(t, long, formatStringList(vc(long, 1), 1, true))
	// the most frequent value is always shown
	assert.Equal(t, long+" (2/66%)... 1 more", formatStringList(vc(long, 2, "a", 1), 3, false))
	assert.Equal(t, "COLLSCAN (2/66%), "+long+" (1/33%)", formatStringList(vc("COLLSCAN", 2, long, 1), 3, true))
}

func logReport(t *testing.T, opts *cliOptions, format string) string {
	queries, err := queriesFromLogs(opts)
	require.NoError(t, err)
	uptime := timeSpan(queries)

	qs := sortQueries(queries.CalcQueriesStats(uptime), opts.OrderBy)
	for i := range qs {
		qs[i].Rank = i + 1
	}
	rep := report{
		Headers:     getHeaders(opts),
		QueryTotals: queries.CalcTotalQueriesStats(uptime),
		QueryStats:  qs,
	}
	out, err := formatResults(rep, format, opts.ShowAll)
	require.NoError(t, err)
	return string(out)
}

func defaultLogOptions(files ...string) *cliOptions {
	return &cliOptions{
		LogFiles:        files,
		OrderBy:         strings.Split(DEFAULT_ORDERBY, ","),
		SkipCollections: sanitizeSkipCollections(strings.Split(DEFAULT_SKIPCOLLECTIONS, ",")),
	}
}

func TestLogReport(t *testing.T) {
	for _, version := range []string{"4.2", "4.4", "6.0", "7.0", "8.0"} {
		t.Run(version, func(t *testing.T) {
			out := logReport(t, defaultLogOptions(sampleLog(t, version)), "text")

			assert.Contains(t, out, "# Totals\n")
			assert.Regexp(t, regexp.MustCompile(`(?m)^# Docs Scanned\s+(\s*[0-9.]+K?){8}\s*$`), out)

			// no internal databases by default
			assert.NotRegexp(t, `(?m)^# Namespace\s+(admin|local|config)\.`, out)

			queries := splitQueries(out)
			require.NotEmpty(t, queries)
			for i, q := range queries {
				assert.True(t, strings.HasPrefix(q, strconv.Itoa(i+1)+":"), q)
				assert.Regexp(t, `(?m)^# Sample time         \S+ \S+ \S+ \S+ \(slowest: \d+ ms\)$`, q)
				assert.Regexp(t, `(?m)^# Query               \{.+\}$`, q)
			}

			// the find on orders by customerId,status: 16 executions from 2 applications
			q := findQuery(t, queries, "FIND orders customerId,status")
			assert.Contains(t, q, "# Count (docs)                    16 \n")
			assert.Contains(t, q, "# App Name            orders-api (8/50%), reporting (8/50%)\n")
			assert.Contains(t, q, "# Client              192.168.65.1\n")
			assert.Contains(t, q, "# User                root\n")
			assert.Regexp(t, `(?m)^# Plan Summary        COLLSCAN \(10/62%\)`, q)
		})
	}
}

func TestLogReportOptions(t *testing.T) {
	log60 := sampleLog(t, "6.0")

	opts := defaultLogOptions(log60)
	opts.Database = "admin"
	out := logReport(t, opts, "text")
	assert.Regexp(t, `(?m)^# Namespace\s+admin\.`, out)
	assert.NotRegexp(t, `(?m)^# Namespace\s+shop\.`, out)

	opts = defaultLogOptions(log60)
	opts.ShowAll = []string{"plan-summary"}
	out = logReport(t, opts, "text")
	q := findQuery(t, splitQueries(out), "FIND orders customerId,status")
	assert.Contains(t, q, "# Plan Summary        COLLSCAN (10/62%), IXSCAN { customerId: 1, status: 1 } (6/37%)\n")

	opts = defaultLogOptions(log60)
	opts.SkipCollections = []string{"orders"}
	out = logReport(t, opts, "text")
	assert.NotContains(t, out, "# Fingerprint         FIND orders")
	assert.Contains(t, out, "# Fingerprint         FIND customers _id")

	// the same file twice doubles the counts
	opts = defaultLogOptions(log60, log60)
	out = logReport(t, opts, "text")
	q = findQuery(t, splitQueries(out), "FIND orders customerId,status")
	assert.Contains(t, q, "# Count (docs)                    32 \n")

	opts = defaultLogOptions(log60)
	opts.Since = time.Date(2026, 11, 4, 11, 33, 4, 0, time.UTC)
	opts.Until = time.Date(2026, 11, 4, 11, 33, 4, 500000000, time.UTC)
	out = logReport(t, opts, "text")
	for _, m := range regexp.MustCompile(`(?m)^# Time range: (.+) to (.+)$`).FindAllStringSubmatch(out, -1) {
		assert.True(t, m[1] >= "2026-11-04 11:33:04" && m[2] <= "2026-11-04 11:33:04.5", m[0])
	}
}

func TestLogReportJSON(t *testing.T) {
	out := logReport(t, defaultLogOptions(sampleLog(t, "6.0")), "json")

	var rep struct {
		Headers    []string
		QueryStats []stats.QueryStats
	}
	require.NoError(t, json.Unmarshal([]byte(out), &rep))
	assert.Contains(t, rep.Headers[1], "Log files: ")

	for _, q := range rep.QueryStats {
		if q.Fingerprint != "FIND orders customerId,status" {
			continue
		}
		assert.False(t, q.SampleTs.IsZero())
		assert.Equal(t, q.QueryTime.Max, q.SampleQueryTime)
		assert.Equal(t, []stats.ValueCount{{Value: "orders-api", Count: 8}, {Value: "reporting", Count: 8}}, q.AppNames)
		assert.NotEmpty(t, q.AppName)
		assert.Equal(t, "192.168.65.1", q.Client)
		return
	}
	t.Fatal("query not found")
}

func TestFormatQPS(t *testing.T) {
	tests := map[float64]string{
		0:        " 0.00",
		2.2222:   " 2.22",
		0.01:     " 0.01",
		1234.5:   " 1234.50",
		0.00872:  " 0.0087",
		0.000873: " 0.00087",
		0.00001:  " 0.00001",
		0.000090: " 0.00009",
	}
	for in, want := range tests {
		assert.Equal(t, want, formatQPS(in), in)
	}
}

// PT-2065: QPS must be calculated using the time covered by the data, not the server uptime
func TestTimeSpanQPS(t *testing.T) {
	t0 := time.Date(2026, 11, 4, 10, 0, 0, 0, time.UTC)
	queries := stats.Queries{
		{Count: 30, FirstSeen: t0.Add(10 * time.Second), LastSeen: t0.Add(50 * time.Second)},
		{Count: 60, FirstSeen: t0, LastSeen: t0.Add(30 * time.Second)},
		{Count: 10, FirstSeen: t0.Add(5 * time.Second), LastSeen: t0.Add(100 * time.Second)},
	}
	assert.Equal(t, int64(100), timeSpan(queries))

	qs := queries.CalcQueriesStats(timeSpan(queries))
	assert.Equal(t, 0.3, qs[0].QPS)
	assert.Equal(t, 0.6, qs[1].QPS)
	assert.Equal(t, 0.1, qs[2].QPS)
	assert.Equal(t, 1.0, queries.CalcTotalQueriesStats(timeSpan(queries)).QPS)

	// less than a second
	assert.Equal(t, int64(1), timeSpan(stats.Queries{{Count: 5, FirstSeen: t0, LastSeen: t0.Add(time.Millisecond)}}))
	assert.Equal(t, int64(1), timeSpan(stats.Queries{}))
}

func findQuery(t *testing.T, queries []string, fingerprint string) string {
	for _, q := range queries {
		if strings.Contains(q, "# Fingerprint         "+fingerprint+"\n") {
			return q
		}
	}
	t.Fatalf("query %q not found", fingerprint)
	return ""
}

var reQueryHeader = regexp.MustCompile(`(?m)^# Query (\d+:)`)

// splitQueries returns the report of each query, starting with the rank
func splitQueries(out string) []string {
	queries := []string{}
	idx := reQueryHeader.FindAllStringSubmatchIndex(out, -1)
	for i, m := range idx {
		end := len(out)
		if i+1 < len(idx) {
			end = idx[i+1][0]
		}
		queries = append(queries, out[m[2]:end])
	}
	return queries
}
