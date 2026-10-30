// This program is copyright 2019-2026 Percona LLC and/or its affiliates.
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
	"database/sql"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync/atomic"
	"testing"
	"text/template"
	"time"

	"github.com/sirupsen/logrus"

	"github.com/percona/percona-toolkit/src/go/lib/pginfo"
	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/internal/tu"
	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/models"
	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/templates"
)

type Test struct {
	name     string
	host     string
	port     string
	username string
	password string
}

func (test Test) dsn(dbName string) string {
	return fmt.Sprintf("host=%s port=%s user=%s password=%s sslmode=disable dbname=%s",
		test.host, test.port, test.username, test.password, dbName)
}

var tests []Test = []Test{
	{"source", tu.IPv4Host, tu.SourcePort, tu.Username, tu.Password},
	{"replica", tu.IPv4Host, tu.ReplicaPort, tu.Username, tu.Password},
	{"source_socket", tu.SocketDir, tu.SourcePort, tu.Username, tu.Password},
}

var logger = logrus.New()

const testSleep = 1

var sandboxAvailable bool

func TestMain(m *testing.M) {
	logger.SetLevel(logrus.WarnLevel)
	if db, err := connect(tests[0].dsn("postgres")); err == nil {
		sandboxAvailable = true
		db.Close()
	}
	code := m.Run()
	os.Exit(code)
}

func skipIfNoSandbox(t *testing.T) {
	if sandboxAvailable {
		return
	}
	if os.Getenv("PT_PG_SANDBOX_REQUIRED") != "" {
		t.Fatalf("no sandbox on %s:%s and PT_PG_SANDBOX_REQUIRED is set", tu.IPv4Host, tu.SourcePort)
	}
	t.Skipf("no sandbox on %s:%s, run sandbox-pg/test-env start", tu.IPv4Host, tu.SourcePort)
}

func skipIfNoSocket(t *testing.T, test Test) {
	if test.host != "" {
		return
	}
	if os.Getenv("PT_PG_SANDBOX_REQUIRED") != "" {
		t.Fatal("no PG_SOCKET_DIR and PT_PG_SANDBOX_REQUIRED is set")
	}
	t.Skip("no unix_socket_directories on this server")
}

func connectTo(t *testing.T, test Test, dbName string) *sql.DB {
	db, err := connect(test.dsn(dbName))
	if err != nil {
		t.Fatalf("Cannot connect to the db using %q: %s", test.dsn(dbName), err)
	}
	return db
}

type statsResetter struct {
	*sql.DB
	t *testing.T
}

func (r statsResetter) reset() {
	if _, err := r.DB.Exec("SELECT pg_stat_reset()"); err != nil {
		r.t.Errorf("Cannot reset the statistics: %s", err)
	}
}

func (r statsResetter) Exec(query string, args ...interface{}) (sql.Result, error) {
	r.reset()
	return r.DB.Exec(query, args...)
}

func (r statsResetter) Query(query string, args ...interface{}) (*sql.Rows, error) {
	r.reset()
	return r.DB.Query(query, args...)
}

func (r statsResetter) QueryRow(query string, args ...interface{}) *sql.Row {
	r.reset()
	return r.DB.QueryRow(query, args...)
}

func renderReport(t *testing.T, info *pginfo.PGInfo) {
	t.Helper()
	tmpl := template.Must(template.New("master").Funcs(funcsMap()).Parse(templates.TPL))
	if err := tmpl.ExecuteTemplate(io.Discard, "report", info); err != nil {
		t.Errorf("Cannot render the report: %s", err)
	}
}

var scratchDBs atomic.Int32

func createScratchDB(t *testing.T) string {
	t.Helper()
	name := fmt.Sprintf("pt_scratch_%d_%d", os.Getpid(), scratchDBs.Add(1))
	source := connectTo(t, tests[0], "postgres")
	defer source.Close()
	if _, err := source.Exec("CREATE DATABASE " + name + " TEMPLATE template0"); err != nil {
		t.Fatalf("Cannot create the %s database: %s", name, err)
	}
	t.Cleanup(func() {
		db, err := connect(tests[0].dsn("postgres"))
		if err != nil {
			t.Errorf("Cannot connect to drop the %s database: %s", name, err)
			return
		}
		defer db.Close()
		if _, err := db.Exec("DROP DATABASE " + name + " WITH (FORCE)"); err != nil {
			t.Errorf("Cannot drop the %s database: %s", name, err)
		}
	})
	return name
}

func execOnConn(t *testing.T, db *sql.DB, queries ...string) {
	t.Helper()
	conn, err := db.Conn(t.Context())
	if err != nil {
		t.Fatalf("Cannot get a connection: %s", err)
	}
	defer conn.Close()
	for _, query := range queries {
		if _, err := conn.ExecContext(t.Context(), query); err != nil {
			t.Fatalf("Cannot run %q: %s", query, err)
		}
	}
}

func waitForReplay(t *testing.T) {
	t.Helper()
	source := connectTo(t, tests[0], "postgres")
	defer source.Close()
	replica := connectTo(t, tests[1], "postgres")
	defer replica.Close()

	var lsn string
	if err := source.QueryRow("SELECT pg_current_wal_lsn()").Scan(&lsn); err != nil {
		t.Fatalf("Cannot get the WAL position on %s: %s", tests[0].name, err)
	}
	for range 100 {
		var replayed bool
		if err := replica.QueryRow("SELECT pg_last_wal_replay_lsn() >= $1::pg_lsn", lsn).Scan(&replayed); err != nil {
			t.Fatalf("Cannot get the replay position on %s: %s", tests[1].name, err)
		}
		if replayed {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("%s has not replayed up to %s in 10 seconds", tests[1].name, lsn)
}

type failingDB struct {
	*sql.DB
	match string
	nth   int32
	seen  atomic.Int32
}

func (f *failingDB) replace(query string) string {
	if strings.Contains(query, f.match) && f.seen.Add(1) == f.nth {
		return "SELECT 1/0"
	}
	return query
}

func (f *failingDB) Query(query string, args ...interface{}) (*sql.Rows, error) {
	return f.DB.Query(f.replace(query), args...)
}

func (f *failingDB) QueryRow(query string, args ...interface{}) *sql.Row {
	return f.DB.QueryRow(f.replace(query), args...)
}

func TestConnection(t *testing.T) {
	skipIfNoSandbox(t)
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			skipIfNoSocket(t, test)
			db := connectTo(t, test, "postgres")
			db.Close()
		})
	}
}

func TestNewWithLogger(t *testing.T) {
	skipIfNoSandbox(t)
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			skipIfNoSocket(t, test)
			db := connectTo(t, test, "postgres")
			defer db.Close()
			if _, err := pginfo.NewWithLogger(db, nil, testSleep, logger); err != nil {
				t.Errorf("Cannot run NewWithLogger using %q: %s", test.dsn("postgres"), err)
			}
		})
	}
}

func TestCollectGlobalInfo(t *testing.T) {
	skipIfNoSandbox(t)
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			skipIfNoSocket(t, test)
			db := connectTo(t, test, "postgres")
			defer db.Close()
			info, err := pginfo.NewWithLogger(db, nil, testSleep, logger)
			if err != nil {
				t.Fatalf("Cannot run NewWithLogger using %q: %s", test.dsn("postgres"), err)
			}
			errs := info.CollectGlobalInfo(db)
			if len(errs) > 0 {
				for _, err := range errs {
					t.Logf("collect error: %s", err)
				}
				t.Fatalf("Cannot collect global information using %q", test.dsn("postgres"))
			}

			var serverVersion string
			if err := db.QueryRow("SHOW server_version").Scan(&serverVersion); err != nil {
				t.Fatalf("SHOW server_version: %s", err)
			}
			segments := info.ServerVersion.Segments()
			if prefix := fmt.Sprintf("%d.%d", segments[0], segments[1]); !strings.HasPrefix(serverVersion, prefix) {
				t.Errorf("ServerVersion = %s, the server reports %s", info.ServerVersion, serverVersion)
			}

			portAndDatadir := map[string]string{}
			for _, row := range info.PortAndDatadir {
				portAndDatadir[row.Name] = row.Setting
			}
			if portAndDatadir["port"] != test.port || portAndDatadir["data_directory"] == "" {
				t.Errorf("PortAndDatadir = %v, want port %s and a data_directory", portAndDatadir, test.port)
			}

			if len(info.ClusterInfo) != 1 {
				t.Fatalf("ClusterInfo has %d rows, want 1", len(info.ClusterInfo))
			}
			cluster := info.ClusterInfo[0]
			if cluster.Usename != test.username {
				t.Errorf("ClusterInfo.Usename = %q, want %q", cluster.Usename, test.username)
			}
			if standby := test.port == tu.ReplicaPort; cluster.IsSlave != standby {
				t.Errorf("ClusterInfo.IsSlave = %v, want %v", cluster.IsSlave, standby)
			}

			activeClient := false
			for _, client := range info.ConnectedClients {
				if string(client.Usename) == test.username && client.State.String == "active" {
					activeClient = true
				}
			}
			if !activeClient {
				t.Errorf("ConnectedClients has no active %s session", test.username)
			}

			portSetting := ""
			for _, setting := range info.Settings {
				if setting.Name == "port" {
					portSetting = setting.Setting
				}
			}
			if portSetting != test.port {
				t.Errorf("Settings port = %q, want %q", portSetting, test.port)
			}
		})
	}
}

func TestCollectPerDatabaseInfo(t *testing.T) {
	skipIfNoSandbox(t)
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			skipIfNoSocket(t, test)
			db := connectTo(t, test, "postgres")
			defer db.Close()
			info, err := pginfo.NewWithLogger(db, nil, testSleep, logger)
			if err != nil {
				t.Fatalf("Cannot run New using %q: %s", test.dsn("postgres"), err)
			}
			names := info.DatabaseNames()
			for _, want := range []string{"pagila", "pt_test"} {
				found := false
				for _, name := range names {
					if name == want {
						found = true
					}
				}
				if !found {
					t.Fatalf("database %s is not in %v", want, names)
				}
			}

			pagila := connectTo(t, test, "pagila")
			defer pagila.Close()
			tx, err := pagila.BeginTx(t.Context(), &sql.TxOptions{ReadOnly: true})
			if err != nil {
				t.Fatalf("Cannot begin a transaction in pagila: %s", err)
			}
			defer tx.Rollback()
			if _, err := tx.Exec("LOCK TABLE film IN ACCESS SHARE MODE"); err != nil {
				t.Fatalf("Cannot lock pagila.film: %s", err)
			}

			for _, dbName := range names {
				conn := connectTo(t, test, dbName)
				if err := info.CollectPerDatabaseInfo(conn, dbName); err != nil {
					t.Errorf("Cannot collect information for the %s database using %q: %s",
						dbName, test.dsn(dbName), err)
				}
				conn.Close()
			}

			filmLocked := false
			for _, access := range info.TableAccess["pagila"] {
				if access.Relname == "film" && access.Datname.String == "pagila" {
					filmLocked = true
				}
			}
			if !filmLocked {
				t.Errorf("TableAccess for pagila does not show the lock held on film")
			}

			for _, dbName := range names {
				table := info.TableCacheHitRatio[dbName]
				if table == nil || !table.Ratio.Valid || table.Ratio.Float64 < 0 || table.Ratio.Float64 > 1 {
					t.Errorf("TableCacheHitRatio for %s = %+v, want a ratio in [0, 1]", dbName, table)
				}
				index := info.IndexCacheHitRatio[dbName]
				if index == nil || !index.Ratio.Valid || index.Ratio.Float64 < 0 || index.Ratio.Float64 > 1 {
					t.Errorf("IndexCacheHitRatio for %s = %+v, want a ratio in [0, 1]", dbName, index)
				}
			}
		})
	}
}

func TestCollectAfterStatsReset(t *testing.T) {
	skipIfNoSandbox(t)
	for _, test := range tests[:2] {
		t.Run(test.name, func(t *testing.T) {
			db := statsResetter{connectTo(t, test, "postgres"), t}
			defer db.Close()
			info, err := pginfo.NewWithLogger(db, nil, testSleep, logger)
			if err != nil {
				t.Fatalf("Cannot run NewWithLogger using %q: %s", test.dsn("postgres"), err)
			}
			if errs := info.CollectGlobalInfo(db); len(errs) > 0 {
				for _, err := range errs {
					t.Logf("collect error: %s", err)
				}
				t.Fatalf("Cannot collect global information using %q", test.dsn("postgres"))
			}

			for _, dbName := range []string{"postgres", "pagila", "pt_test"} {
				conn := statsResetter{connectTo(t, test, dbName), t}
				if err := info.CollectPerDatabaseInfo(conn, dbName); err != nil {
					t.Errorf("Cannot collect information for the %s database using %q: %s",
						dbName, test.dsn(dbName), err)
				}
				conn.Close()
			}

			renderReport(t, info)
		})
	}
}

func TestTableCacheHitRatioAfterStatsReset(t *testing.T) {
	skipIfNoSandbox(t)
	for _, tc := range []struct {
		name   string
		table  string
		access []string
		stats  string
		want   float64
	}{
		{
			name:   "index lookups that find nothing",
			table:  "CREATE TABLE t (id int PRIMARY KEY) WITH (autovacuum_enabled = off)",
			access: []string{"SET enable_seqscan = off", "SET enable_bitmapscan = off", "SELECT id FROM t WHERE id = -1"},
			stats:  "sum(heap_blks_hit) = 0 AND sum(heap_blks_read) = 0 AND sum(idx_blks_hit) > 0",
			want:   0,
		},
		{
			name:   "cached sequential scan without indexes",
			table:  "CREATE TABLE t (id int) WITH (autovacuum_enabled = off)",
			access: []string{"SELECT count(*) FROM t"},
			stats:  "sum(heap_blks_hit) > 0 AND sum(heap_blks_read) = 0 AND sum(idx_blks_hit) IS NULL",
			want:   1,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dbName := createScratchDB(t)
			source := connectTo(t, tests[0], dbName)
			execOnConn(t, source, tc.table, "INSERT INTO t SELECT generate_series(1, 1000)", "SELECT pg_stat_force_next_flush()")
			source.Close()
			waitForReplay(t)

			for _, test := range tests[:2] {
				t.Run(test.name, func(t *testing.T) {
					db := connectTo(t, test, dbName)
					defer db.Close()
					queries := append([]string{"SELECT pg_stat_reset()"}, tc.access...)
					execOnConn(t, db, append(queries, "SELECT pg_stat_force_next_flush()")...)

					query := "SELECT (" + tc.stats + ") IS TRUE, " +
						"row(sum(heap_blks_hit), sum(heap_blks_read), sum(idx_blks_hit))::text FROM pg_statio_user_tables"
					var ok bool
					var sums string
					if err := db.QueryRow(query).Scan(&ok, &sums); err != nil {
						t.Fatalf("Cannot read pg_statio_user_tables: %s", err)
					}
					if !ok {
						t.Fatalf("after %q the heap hit, heap read and index hit sums are %s, want %s", tc.access, sums, tc.stats)
					}

					ratio, err := models.GetTableCacheHitRatio(db)
					if err != nil {
						t.Fatalf("Cannot get the table cache hit ratio: %s", err)
					}
					if !ratio.Ratio.Valid || ratio.Ratio.Float64 != tc.want {
						t.Errorf("TableCacheHitRatio = %+v, want %v", ratio.Ratio, tc.want)
					}
				})
			}
		})
	}
}

func TestReportAfterFailedDatabaseQuery(t *testing.T) {
	skipIfNoSandbox(t)
	for _, tc := range []struct {
		view   string
		stored func(*pginfo.PGInfo) bool
	}{
		{"pg_locks", func(info *pginfo.PGInfo) bool { _, ok := info.TableAccess["pt_test"]; return ok }},
		{"pg_statio_user_tables", func(info *pginfo.PGInfo) bool { _, ok := info.TableCacheHitRatio["pt_test"]; return ok }},
		{"pg_statio_user_indexes", func(info *pginfo.PGInfo) bool { _, ok := info.IndexCacheHitRatio["pt_test"]; return ok }},
	} {
		t.Run(tc.view, func(t *testing.T) {
			db := connectTo(t, tests[0], "postgres")
			defer db.Close()
			info, err := pginfo.NewWithLogger(db, nil, testSleep, logger)
			if err != nil {
				t.Fatalf("Cannot run NewWithLogger using %q: %s", tests[0].dsn("postgres"), err)
			}

			conn := &failingDB{DB: connectTo(t, tests[0], "pt_test"), match: tc.view, nth: 1}
			defer conn.Close()
			if err := info.CollectPerDatabaseInfo(conn, "pt_test"); err == nil {
				t.Fatalf("CollectPerDatabaseInfo did not fail when the %s query failed", tc.view)
			}
			if tc.stored(info) {
				t.Errorf("the %s query failed, but its result for pt_test was stored", tc.view)
			}

			renderReport(t, info)
		})
	}
}

func TestReportAfterFailedCountersPass(t *testing.T) {
	skipIfNoSandbox(t)
	for _, pass := range []int32{1, 2} {
		t.Run(fmt.Sprintf("pass %d", pass), func(t *testing.T) {
			db := &failingDB{DB: connectTo(t, tests[0], "postgres"), match: "xact_commit", nth: pass}
			defer db.Close()
			info, err := pginfo.NewWithLogger(db, nil, testSleep, logger)
			if err != nil {
				t.Fatalf("Cannot run NewWithLogger using %q: %s", tests[0].dsn("postgres"), err)
			}

			failed := false
			for _, err := range info.CollectGlobalInfo(db) {
				if strings.Contains(err.Error(), "division by zero") {
					failed = true
				}
			}
			if !failed {
				t.Fatalf("CollectGlobalInfo did not report the failed counters pass %d", pass)
			}
			if len(info.Counters) != 0 {
				t.Errorf("Counters has %d databases after a failed pass, want none", len(info.Counters))
			}

			renderReport(t, info)
		})
	}
}

func TestReplicationTopology(t *testing.T) {
	skipIfNoSandbox(t)

	source := connectTo(t, tests[0], "postgres")
	defer source.Close()

	var inRecovery bool
	if err := source.QueryRow("SELECT pg_is_in_recovery()").Scan(&inRecovery); err != nil {
		t.Fatalf("pg_is_in_recovery on %s: %s", tests[0].name, err)
	}
	if inRecovery {
		t.Errorf("%s is in recovery, expected the primary", tests[0].name)
	}

	info, err := pginfo.NewWithLogger(source, nil, testSleep, logger)
	if err != nil {
		t.Fatalf("Cannot run NewWithLogger using %q: %s", tests[0].dsn("postgres"), err)
	}
	if errs := info.CollectGlobalInfo(source); len(errs) > 0 {
		for _, err := range errs {
			t.Logf("collect error: %s", err)
		}
		t.Fatalf("Cannot collect global information using %q", tests[0].dsn("postgres"))
	}
	if len(info.SlaveHosts10) != 1 {
		t.Fatalf("%s has %d standbys, want 1", tests[0].name, len(info.SlaveHosts10))
	}
	standby := info.SlaveHosts10[0]
	if standby.State.String != "streaming" || standby.ClientAddr.String != tu.IPv4Host {
		t.Errorf("standby on %s: state %q from %q, want \"streaming\" from %q",
			tests[0].name, standby.State.String, standby.ClientAddr.String, tu.IPv4Host)
	}
	if !standby.ByteLag.Valid || standby.ByteLag.Float64 < 0 {
		t.Errorf("standby on %s: byte lag %+v, want a non-negative number", tests[0].name, standby.ByteLag)
	}

	replica := connectTo(t, tests[1], "postgres")
	defer replica.Close()

	if err := replica.QueryRow("SELECT pg_is_in_recovery()").Scan(&inRecovery); err != nil {
		t.Fatalf("pg_is_in_recovery on %s: %s", tests[1].name, err)
	}
	if !inRecovery {
		t.Errorf("%s is not in recovery, expected the standby", tests[1].name)
	}

	replicaInfo, err := pginfo.NewWithLogger(replica, nil, testSleep, logger)
	if err != nil {
		t.Fatalf("Cannot run NewWithLogger using %q: %s", tests[1].dsn("postgres"), err)
	}
	if errs := replicaInfo.CollectGlobalInfo(replica); len(errs) > 0 {
		for _, err := range errs {
			t.Logf("collect error: %s", err)
		}
		t.Fatalf("Cannot collect global information using %q", tests[1].dsn("postgres"))
	}
	if len(replicaInfo.SlaveHosts10) != 0 {
		t.Errorf("%s reports %d standbys of its own, want none", tests[1].name, len(replicaInfo.SlaveHosts10))
	}
}

func TestReportShowsPortAndDataDirectory(t *testing.T) {
	skipIfNoSandbox(t)

	db := connectTo(t, tests[0], "postgres")
	defer db.Close()

	info, err := pginfo.NewWithLogger(db, nil, testSleep, logger)
	if err != nil {
		t.Fatalf("Cannot run NewWithLogger using %q: %s", tests[0].dsn("postgres"), err)
	}
	if errs := info.CollectGlobalInfo(db); len(errs) > 0 {
		for _, err := range errs {
			t.Logf("collect error: %s", err)
		}
		t.Fatalf("Cannot collect global information using %q", tests[0].dsn("postgres"))
	}

	tmpl := template.Must(template.New("master").Funcs(funcsMap()).Parse(templates.TPL))
	var out bytes.Buffer
	if err := tmpl.ExecuteTemplate(&out, "port_and_datadir", info.PortAndDatadir); err != nil {
		t.Fatalf("Cannot render port_and_datadir: %s", err)
	}

	for _, row := range []string{
		`\| port +\| ` + tu.SourcePort + ` +\|`,
		`\| data_directory +\| /\S+ +\|`,
	} {
		if !regexp.MustCompile(row).Match(out.Bytes()) {
			t.Errorf("no row matching %q in:\n%s", row, out.String())
		}
	}
}

const semVerRE = `(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)` +
	`(?:-(?:(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?` +
	`(?:\+(?:[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?`

func TestVersionOption(t *testing.T) {
	out, err := exec.Command("../../../bin/"+toolname, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	re := regexp.MustCompile(toolname + `\n.*Version v?` + semVerRE + `\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", toolname, out)
	}
}

func TestVerboseEnablesInfoLog(t *testing.T) {
	skipIfNoSandbox(t)

	conn := []string{
		"--host=" + tu.IPv4Host,
		"--port=" + tu.SourcePort,
		"--username=" + tu.Username,
		"--password=" + tu.Password,
		"--disable-ssl",
		"--sleep=1",
	}
	for _, test := range []struct {
		name     string
		args     []string
		wantInfo bool
	}{
		{"default", conn, false},
		{"verbose", append([]string{"--verbose"}, conn...), true},
	} {
		t.Run(test.name, func(t *testing.T) {
			var stderr bytes.Buffer
			cmd := exec.Command("../../../bin/"+toolname, test.args...)
			cmd.Stderr = &stderr
			if err := cmd.Run(); err != nil {
				t.Fatalf("%s %v: %s\n%s", toolname, test.args, err, stderr.String())
			}
			gotInfo := strings.Contains(stderr.String(), `msg="Connection OK"`)
			if gotInfo != test.wantInfo {
				t.Errorf("info log shown = %v, want %v; stderr:\n%s", gotInfo, test.wantInfo, stderr.String())
			}
		})
	}
}
