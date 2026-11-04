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

package logparser

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"

	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
)

func logsDir(t *testing.T) string {
	root, err := tutil.RootPath()
	require.NoError(t, err)
	return filepath.Join(root, "src", "go", "tests", "logs")
}

func parseFile(t *testing.T, p *Parser, file string) []proto.SystemProfile {
	f, err := os.Open(file)
	require.NoError(t, err)
	defer f.Close()

	docs := []proto.SystemProfile{}
	err = p.Parse(f, func(doc proto.SystemProfile) error {
		docs = append(docs, doc)
		return nil
	})
	require.NoError(t, err)
	return docs
}

// The sample logs were generated running the same workload against each version, twice
// (with appName orders-api and reporting) using the root user.
func TestSampleLogs(t *testing.T) {
	tests := []struct {
		version  string
		counters Counters
	}{
		{"4.2", Counters{Lines: 193, SlowQueries: 134, Parsed: 128, Ignored: 6}},
		{"4.4", Counters{Lines: 160, SlowQueries: 130, Parsed: 120, Ignored: 10}},
		{"6.0", Counters{Lines: 159, SlowQueries: 129, Parsed: 119, Ignored: 10}},
		{"7.0", Counters{Lines: 159, SlowQueries: 129, Parsed: 119, Ignored: 10}},
		{"8.0", Counters{Lines: 160, SlowQueries: 130, Parsed: 120, Ignored: 10}},
	}

	wantFingerprints := []string{
		"AGGREGATE orders _id,n,status",
		"CREATEINDEXES orders",
		"DISTINCT orders customerId,status",
		"FIND customers _id",
		"FIND orders created,customerId",
		"FIND orders customerId",
		"FIND orders customerId,status",
		"FIND orders email",
		"FIND orders status,total",
		"FINDANDMODIFY orders customerId,status",
		"GETMORE orders",
		"INSERT customers",
		"INSERT orders",
		"REMOVE orders customerId,status",
		"UPDATE orders _id",
		"UPDATE orders customerId",
	}

	for _, test := range tests {
		t.Run(test.version, func(t *testing.T) {
			p := New(Options{})
			docs := parseFile(t, p, filepath.Join(logsDir(t), "mongod-"+test.version+".log"))
			assert.Equal(t, test.counters, p.Counters())
			assert.Len(t, docs, test.counters.Parsed)

			fp := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters())
			s := stats.New(fp)
			for _, doc := range docs {
				require.NoError(t, s.Add(doc), "%+v", doc)
			}

			fingerprints := map[string]bool{}
			for _, q := range s.Queries() {
				// Other namespaces come from the docker image initialization
				if !strings.HasPrefix(q.Namespace, "shop.") {
					continue
				}
				fingerprints[q.Fingerprint] = true
				assert.Equal(t, map[string]int{"root": q.Count}, q.Users, q.Fingerprint)
				assert.Equal(t, map[string]int{"192.168.65.1": q.Count}, q.Clients, q.Fingerprint)
				assert.Equal(t, map[string]int{"orders-api": q.Count / 2, "reporting": q.Count / 2}, q.AppNames, q.Fingerprint)
			}
			for _, fp := range wantFingerprints {
				assert.True(t, fingerprints[fp], "missing fingerprint %q", fp)
			}

			for _, doc := range docs {
				if doc.Ns != "shop.orders" || doc.Op != "query" {
					continue
				}
				assert.False(t, doc.Ts.IsZero())
				assert.Contains(t, []string{"orders-api", "reporting"}, doc.AppName)
				assert.NotEmpty(t, doc.PlanSummary)
				assert.NotEmpty(t, doc.QueryHash)
				assert.Equal(t, "op_msg", doc.Protocol)
				assert.Positive(t, doc.Locks.Global.AcquireCount.ReadShared)
			}
		})
	}
}

func TestParseJSONLine(t *testing.T) {
	line := `{"t":{"$date":"2026-11-03T10:15:02.114+00:00"},"s":"I","c":"COMMAND","id":51803,"ctx":"conn12",` +
		`"msg":"Slow query","attr":{"type":"command","ns":"shop.orders","appName":"orders-api",` +
		`"command":{"find":"orders","filter":{"customerId":1234,"status":"open"},"sort":{"total":-1},"comment":"dashboard",` +
		`"lsid":{"id":{"$uuid":"4fcbce49-7cd0-4601-9de1-0029474c9d28"}},"$db":"shop"},"planSummary":"IXSCAN { customerId: 1 }",` +
		`"keysExamined":120,"docsExamined":100,"cursorExhausted":true,"numYields":3,"nreturned":10,"planCacheShapeHash":"2BDC1CB3",` +
		`"reslen":2340,"locks":{"Global":{"acquireCount":{"r":12}},"Database":{"acquireCount":{"r":11}},"Collection":{"acquireCount":{"r":10}}},` +
		`"storage":{"data":{"bytesRead":1234,"timeReadingMicros":56}},"remote":"10.0.4.17:51234","protocol":"op_msg","durationMillis":103}}`

	p := New(Options{})
	doc, ok := p.ParseLine([]byte(line))
	require.True(t, ok)

	assert.Equal(t, time.Date(2026, 11, 3, 10, 15, 2, 114000000, time.UTC), doc.Ts.UTC())
	assert.Equal(t, "query", doc.Op)
	assert.Equal(t, "shop.orders", doc.Ns)
	assert.Equal(t, "orders-api", doc.AppName)
	assert.Equal(t, "orders", doc.Command.Map()["find"])
	assert.Equal(t, "IXSCAN { customerId: 1 }", doc.PlanSummary)
	assert.Equal(t, 120, doc.KeysExamined)
	assert.Equal(t, 100, doc.DocsExamined)
	assert.Equal(t, 3, doc.NumYield)
	assert.Equal(t, 10, doc.Nreturned)
	assert.Equal(t, "2BDC1CB3", doc.QueryHash)
	assert.Equal(t, 2340, doc.ResponseLength)
	assert.Equal(t, 12, doc.Locks.Global.AcquireCount.ReadShared)
	assert.Equal(t, 11, doc.Locks.Database.AcquireCount.ReadShared)
	assert.Equal(t, 10, doc.Locks.Collection.AcquireCount.ReadShared)
	assert.Equal(t, int64(1234), doc.Storage.Data.BytesRead)
	assert.Equal(t, int64(56), doc.Storage.Data.TimeReadingMicros)
	assert.Equal(t, "10.0.4.17", doc.Client)
	assert.Equal(t, 103, doc.Millis)
	assert.Equal(t, "dashboard", doc.Comments)

	fp, err := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters()).Fingerprint(doc)
	require.NoError(t, err)
	assert.Equal(t, "FIND orders customerId,status,total", fp.Fingerprint)
}

func TestParseLegacyLine(t *testing.T) {
	line := `2019-05-14T10:22:31.123-0300 I  COMMAND  [conn12] command shop.orders appName: "orders api" ` +
		`command: find { find: "orders", filter: { _id: ObjectId('5cd8a1f2e4b0c1a2b3c4d5e6'), ts: { $gte: new Date(1557829351123) }, ` +
		`name: /^abc/i, code: { $in: [ 1, -2.5, "x" ] }, ok: true, nothing: null, u: UUID("4fcbce49-7cd0-4601-9de1-0029474c9d28") }, ` +
		`sort: { total: -1 }, $db: "shop" } planSummary: IXSCAN { _id: 1 }, IXSCAN { ts: 1 } keysExamined:120 docsExamined:100 ` +
		`fromMultiPlanner:1 cursorExhausted:1 numYields:3 nreturned:10 queryHash:2BDC1CB3 planCacheKey:2BDC1CB3 reslen:2340 ` +
		`locks:{ Global: { acquireCount: { r: 12 } }, Database: { acquireCount: { r: 11 } }, Collection: { acquireCount: { r: 10 } } } ` +
		`storage:{ data: { bytesRead: 1234, timeReadingMicros: 56 } } protocol:op_msg 103ms`

	p := New(Options{})
	doc, ok := p.ParseLine([]byte(line))
	require.True(t, ok)

	assert.Equal(t, time.Date(2019, 5, 14, 13, 22, 31, 123000000, time.UTC), doc.Ts.UTC())
	assert.Equal(t, "query", doc.Op)
	assert.Equal(t, "shop.orders", doc.Ns)
	assert.Equal(t, "orders api", doc.AppName)
	assert.Equal(t, "IXSCAN { _id: 1 }, IXSCAN { ts: 1 }", doc.PlanSummary)
	assert.Equal(t, 120, doc.KeysExamined)
	assert.Equal(t, 100, doc.DocsExamined)
	assert.Equal(t, 3, doc.NumYield)
	assert.Equal(t, 10, doc.Nreturned)
	assert.Equal(t, "2BDC1CB3", doc.QueryHash)
	assert.Equal(t, 2340, doc.ResponseLength)
	assert.Equal(t, 12, doc.Locks.Global.AcquireCount.ReadShared)
	assert.Equal(t, 10, doc.Locks.Collection.AcquireCount.ReadShared)
	assert.Equal(t, int64(1234), doc.Storage.Data.BytesRead)
	assert.Equal(t, "op_msg", doc.Protocol)
	assert.Equal(t, 103, doc.Millis)

	filter := doc.Command.Map()["filter"].(bson.D).Map()
	oid, _ := primitive.ObjectIDFromHex("5cd8a1f2e4b0c1a2b3c4d5e6")
	assert.Equal(t, oid, filter["_id"])
	assert.Equal(t, bson.D{{Key: "$gte", Value: primitive.DateTime(1557829351123)}}, filter["ts"])
	assert.Equal(t, primitive.Regex{Pattern: "^abc", Options: "i"}, filter["name"])
	assert.Equal(t, bson.D{{Key: "$in", Value: bson.A{int32(1), -2.5, "x"}}}, filter["code"])
	assert.Equal(t, true, filter["ok"])
	assert.Nil(t, filter["nothing"])
	assert.Equal(t, `UUID("4fcbce49-7cd0-4601-9de1-0029474c9d28")`, filter["u"])

	fp, err := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters()).Fingerprint(doc)
	require.NoError(t, err)
	assert.Equal(t, "FIND orders _id,code,name,nothing,ok,total,ts,u", fp.Fingerprint)
}

func TestParseLegacyWrites(t *testing.T) {
	lines := []string{
		`2026-11-04T11:33:02.165+0000 I  WRITE    [conn3] update shop.orders appName: "app" command: { q: { _id: 10 }, u: { $set: { status: "closed" } }, multi: false, upsert: false } planSummary: IDHACK keysExamined:1 docsExamined:1 nMatched:1 nModified:0 numYields:0 locks:{} storage:{} 5ms`,
		`2026-11-04T11:33:02.166+0000 I  COMMAND  [conn3] command shop.$cmd appName: "app" command: update { update: "orders", updates: [ { q: { _id: 10 }, u: { $set: { status: "closed" } } } ], ordered: true, $db: "shop" } numYields:0 reslen:60 locks:{} protocol:op_msg 6ms`,
		`2026-11-04T11:33:02.168+0000 I  WRITE    [conn3] remove shop.orders appName: "app" command: { q: { customerId: 49, status: "closed" }, limit: 0 } planSummary: COLLSCAN keysExamined:0 docsExamined:3000 ndeleted:40 keysDeleted:40 numYields:23 locks:{} storage:{} 7ms`,
		`2026-11-04T11:33:02.134+0000 I  COMMAND  [conn3] command shop.orders appName: "app" command: insert { insert: "orders", documents: 3000, ordered: true, $db: "shop" } ninserted:3000 keysInserted:3000 numYields:0 reslen:45 locks:{} storage:{} protocol:op_msg 12ms`,
		// MongoDB 3.2 format
		`2017-02-03T16:01:37.484-0300 I WRITE    [conn1] update test.coll query: { a: { $gte: 2 } } update: { $set: { c: 1 }, $inc: { a: -10 } } keysExamined:0 docsExamined:3 nMatched:1 nModified:1 numYields:0 locks:{ Global: { acquireCount: { r: 2, w: 2 } } } 2ms`,
	}

	p := New(Options{})
	fp := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters())
	got := []string{}
	for _, line := range lines {
		doc, ok := p.ParseLine([]byte(line))
		if !ok {
			continue
		}
		f, err := fp.Fingerprint(doc)
		require.NoError(t, err)
		got = append(got, f.Fingerprint)
	}
	assert.Equal(t, []string{"UPDATE orders _id", "REMOVE orders customerId,status", "INSERT orders", "UPDATE coll a"}, got)
	assert.Equal(t, Counters{Lines: 5, SlowQueries: 5, Parsed: 4, Ignored: 1}, p.Counters())
}

// The command level entry of a write batch is ignored only if its statements were logged
func TestWriteBatches(t *testing.T) {
	stmt := func(ctx, ts string) string {
		return `{"t":{"$date":"2026-11-03T10:00:` + ts + `.000+00:00"},"s":"I","c":"WRITE","id":51803,"ctx":"` + ctx + `","msg":"Slow query",` +
			`"attr":{"type":"update","ns":"airline.flights","command":{"q":{"flight_id":1},"u":{"$set":{"a":1}},"multi":false,"upsert":false},` +
			`"planSummary":"IXSCAN { flight_id: 1 }","keysExamined":1,"docsExamined":1,"durationMillis":250}}`
	}
	batch := func(ctx, ts, cmd string) string {
		return `{"t":{"$date":"2026-11-03T10:00:` + ts + `.000+00:00"},"s":"I","c":"COMMAND","id":51803,"ctx":"` + ctx + `","msg":"Slow query",` +
			`"attr":{"type":"command","ns":"airline.$cmd","command":{"` + cmd + `":"flights","ordered":true,"lsid":{"id":{"$uuid":"4fcbce49-7cd0-4601-9de1-0029474c9d28"}},"txnNumber":3,"$db":"airline"},` +
			`"waitForWriteConcernDurationMillis":240,"reslen":60,"durationMillis":260}}`
	}
	find := func(ctx, ts string) string {
		return `{"t":{"$date":"2026-11-03T10:00:` + ts + `.000+00:00"},"s":"I","c":"COMMAND","id":51803,"ctx":"` + ctx + `","msg":"Slow query",` +
			`"attr":{"type":"command","ns":"airline.flights","command":{"find":"flights","filter":{"a":1}},"durationMillis":300}}`
	}

	lines := []string{
		stmt("conn1", "01"), batch("conn1", "02", "update"), // statement logged: batch ignored
		batch("conn2", "03", "update"),                      // no statement: reported
		stmt("conn3", "04"), batch("conn4", "05", "delete"), // statement on another connection: reported
		batch("conn3", "06", "update"),                                           // conn3 statement: ignored
		stmt("conn5", "07"), find("conn5", "08"), batch("conn5", "09", "update"), // the find resets conn5: reported
		`2026-11-03T10:00:10.000+0000 I  COMMAND  [conn6] command airline.$cmd command: delete { delete: "flights", deletes: [ { q: { flight_id: 5, status: "x" }, limit: 1 } ], ordered: true, $db: "airline" } numYields:0 reslen:60 locks:{} protocol:op_query 300ms`,
	}

	p := New(Options{})
	fp := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters())
	got := []string{}
	for _, line := range lines {
		doc, ok := p.ParseLine([]byte(line))
		if !ok {
			continue
		}
		f, err := fp.Fingerprint(doc)
		require.NoError(t, err)
		got = append(got, doc.Ts.Format("05")+" "+f.Namespace+" "+f.Fingerprint)
	}
	assert.Equal(t, []string{
		"01 airline.flights UPDATE flights flight_id",
		"03 airline.flights UPDATE flights (batch)",
		"04 airline.flights UPDATE flights flight_id",
		"05 airline.flights DELETE flights (batch)",
		"07 airline.flights UPDATE flights flight_id",
		"08 airline.flights FIND flights a",
		"09 airline.flights UPDATE flights (batch)",
		"10 airline.flights DELETE flights flight_id,status (batch)",
	}, got)
	assert.Equal(t, 2, p.Counters().Ignored)
}

func TestUnparsable(t *testing.T) {
	lines := []string{
		// truncated command
		`2026-11-04T11:33:02.145+0000 I  COMMAND  [conn3] command shop.orders command: find { find: "orders", filter: { customerId: 0, status: "op ...  planSummary: COLLSCAN 0ms`,
		// invalid json
		`{"t":{"$date":"2026-11-04T11:33:06.273+00:00"},"s":"I","c":"COMMAND","id":51803,"ctx":"conn3","msg":"Slow query","attr":{"type":"command"`,
		// not slow queries
		`2026-11-04T11:33:02.145+0000 I  NETWORK  [conn3] received client metadata from 10.0.0.1:1234 conn3: { driver: { name: "x" } }`,
		`{"t":{"$date":"2026-11-04T11:33:06.273+00:00"},"s":"I","c":"NETWORK","id":22943,"ctx":"listener","msg":"Connection accepted","attr":{"remote":"10.0.0.2:4567","connectionId":4}}`,
		`random text`,
		``,
	}

	errors := 0
	p := New(Options{OnError: func(int, error) { errors++ }})
	for _, line := range lines {
		_, ok := p.ParseLine([]byte(line))
		assert.False(t, ok, line)
	}
	assert.Equal(t, Counters{Lines: 6, SlowQueries: 2, Unparsable: 2}, p.Counters())
	assert.Equal(t, 2, errors)
}

func TestConnectionTracking(t *testing.T) {
	lines := []string{
		`{"t":{"$date":"2026-11-04T11:33:00.000+00:00"},"s":"I","c":"NETWORK","id":22943,"ctx":"listener","msg":"Connection accepted","attr":{"remote":"10.0.0.2:4567","connectionId":4}}`,
		`{"t":{"$date":"2026-11-04T11:33:00.001+00:00"},"s":"I","c":"ACCESS","id":5286306,"ctx":"conn4","msg":"Successfully authenticated","attr":{"client":"10.0.0.2:4567","isSpeculative":false,"mechanism":"SCRAM-SHA-256","user":"app","db":"admin"}}`,
		`{"t":{"$date":"2026-11-04T11:33:00.002+00:00"},"s":"I","c":"COMMAND","id":51803,"ctx":"conn4","msg":"Slow query","attr":{"type":"command","ns":"shop.orders","command":{"find":"orders","filter":{}},"durationMillis":1}}`,
		`{"t":{"$date":"2026-11-04T11:33:00.003+00:00"},"s":"I","c":"NETWORK","id":22944,"ctx":"conn4","msg":"Connection ended","attr":{"remote":"10.0.0.2:4567","connectionId":4}}`,
		`{"t":{"$date":"2026-11-04T11:33:00.004+00:00"},"s":"I","c":"COMMAND","id":51803,"ctx":"conn4","msg":"Slow query","attr":{"type":"command","ns":"shop.orders","command":{"find":"orders","filter":{}},"durationMillis":1}}`,
		`2019-05-14T10:22:30.000+0000 I  NETWORK  [listener] connection accepted from [::1]:52512 #7 (1 connection now open)`,
		`2019-05-14T10:22:30.001+0000 I  ACCESS   [conn7] Successfully authenticated as principal legacy on admin from client [::1]:52512`,
		`2019-05-14T10:22:31.000+0000 I  COMMAND  [conn7] command shop.orders command: find { find: "orders", filter: {} } planSummary: EOF 1ms`,
	}

	p := New(Options{})
	docs := []proto.SystemProfile{}
	for _, line := range lines {
		if doc, ok := p.ParseLine([]byte(line)); ok {
			docs = append(docs, doc)
		}
	}
	require.Len(t, docs, 3)
	assert.Equal(t, "10.0.0.2", docs[0].Client)
	assert.Equal(t, "app@admin", docs[0].User)
	assert.Equal(t, "", docs[1].Client)
	assert.Equal(t, "", docs[1].User)
	assert.Equal(t, "::1", docs[2].Client)
	assert.Equal(t, "legacy@admin", docs[2].User)
}

func TestTimeRange(t *testing.T) {
	since := time.Date(2026, 11, 4, 11, 33, 4, 0, time.UTC)
	until := time.Date(2026, 11, 4, 11, 33, 5, 0, time.UTC)
	p := New(Options{Since: since, Until: until})
	docs := parseFile(t, p, filepath.Join(logsDir(t), "mongod-6.0.log"))

	require.NotEmpty(t, docs)
	for _, doc := range docs {
		assert.False(t, doc.Ts.Before(since), doc.Ts)
		assert.False(t, doc.Ts.After(until), doc.Ts)
	}
	c := p.Counters()
	assert.Positive(t, c.OutOfRange)
	assert.Equal(t, c.SlowQueries, c.Parsed+c.OutOfRange+c.Ignored)
}

func TestParseShellDoc(t *testing.T) {
	tests := []struct {
		in   string
		want bson.D
	}{
		{`{}`, bson.D{}},
		{`{ a: 1, "b c": 'x', d: { e: [ 1, { f: 5000000000 } ] } }`, bson.D{
			{Key: "a", Value: int32(1)},
			{Key: "b c", Value: "x"},
			{Key: "d", Value: bson.D{{Key: "e", Value: bson.A{int32(1), bson.D{{Key: "f", Value: int64(5000000000)}}}}}},
		}},
		{`{ a: "say \"hi\"", b: 1.5e3, c: -inf, d: MinKey, e: undefined }`, bson.D{
			{Key: "a", Value: `say "hi"`},
			{Key: "b", Value: 1500.0},
			{Key: "c", Value: math.Inf(-1)},
			{Key: "d", Value: primitive.MinKey{}},
			{Key: "e", Value: primitive.Undefined{}},
		}},
		{`{ ts: Timestamp(1557829351, 1), old: Timestamp 1557829351000|1, bin: BinData(0, 4142), n: NumberLong(5), dec: NumberDecimal("1.5") }`, bson.D{
			{Key: "ts", Value: "Timestamp(1557829351, 1)"},
			{Key: "old", Value: "Timestamp 1557829351000|1"},
			{Key: "bin", Value: "BinData(0, 4142)"},
			{Key: "n", Value: int64(5)},
			{Key: "dec", Value: mustDecimal(t, "1.5")},
		}},
		{`{ mapreduce: "coll", map: function () { emit(this.a, "}"); }, out: { inline: 1 } }`, bson.D{
			{Key: "mapreduce", Value: "coll"},
			{Key: "map", Value: primitive.JavaScript(`function () { emit(this.a, "}"); }`)},
			{Key: "out", Value: bson.D{{Key: "inline", Value: int32(1)}}},
		}},
	}
	for _, test := range tests {
		got, n, err := parseShellDoc(test.in + " trailing")
		require.NoError(t, err, test.in)
		assert.Equal(t, len(test.in), n, test.in)
		assert.Equal(t, test.want, got, test.in)
	}

	for _, in := range []string{`{ a: 1`, `{ a: "x }`, `{ a: { b: 1 }`, `{ : 1 }`, `{ a 1 }`, `{ a: 1 ...`} {
		_, _, err := parseShellDoc(in)
		assert.Error(t, err, in)
	}
}

func mustDecimal(t *testing.T, s string) primitive.Decimal128 {
	d, err := primitive.ParseDecimal128(s)
	require.NoError(t, err)
	return d
}
