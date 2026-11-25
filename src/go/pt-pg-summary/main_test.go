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
	"os"
	"os/exec"
	"regexp"
	"strings"
	"testing"
	"text/template"

	"github.com/sirupsen/logrus"

	"github.com/percona/percona-toolkit/src/go/lib/pginfo"
	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/internal/tu"
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
