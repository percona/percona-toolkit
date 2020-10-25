package main

import (
	"fmt"
	"os"
	"testing"

	"github.com/percona/percona-toolkit/src/go/lib/pginfo"
	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/internal/tu"

	"github.com/sirupsen/logrus"
)

type Test struct {
	name     string
	host     string
	port     string
	username string
	password string
}

var tests []Test = []Test{
	{"IPv4PG9", tu.IPv4Host, tu.IPv4PG9Port, tu.Username, tu.Password},
	{"IPv4PG10", tu.IPv4Host, tu.IPv4PG10Port, tu.Username, tu.Password},
	{"IPv4PG11", tu.IPv4Host, tu.IPv4PG11Port, tu.Username, tu.Password},
	{"IPv4PG12", tu.IPv4Host, tu.IPv4PG12Port, tu.Username, tu.Password},
}

var logger = logrus.New()

func TestMain(m *testing.M) {
	logger.SetLevel(logrus.WarnLevel)
	os.Exit(m.Run())
}

func TestConnection(t *testing.T) {
	// use an "external" IP to simulate a remote host
	tests := append(tests, Test{"remote_host", tu.PG9DockerIP, tu.DefaultPGPort, tu.Username, tu.Password})
	// use IPV6 for PostgreSQL 9
	// tests := append(tests, Test{"IPV6", tu.IPv6Host, tu.IPv6PG9Port, tu.Username, tu.Password})
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s sslmode=disable dbname=%s",
				test.host, test.port, test.username, test.password, "postgres")
			if _, err := connect(dsn); err != nil {
				t.Errorf("Cannot connect to the db using %q: %s", dsn, err)
			}
		})
	}
}

func TestNewWithLogger(t *testing.T) {
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s sslmode=disable dbname=%s",
				test.host, test.port, test.username, test.password, "postgres")
			db, err := connect(dsn)
			if err != nil {
				t.Errorf("Cannot connect to the db using %q: %s", dsn, err)
			}
			if _, err := pginfo.NewWithLogger(db, nil, 30, logger); err != nil {
				t.Errorf("Cannot run NewWithLogger using %q: %s", dsn, err)
			}
		})
	}
}

func TestCollectGlobalInfo(t *testing.T) {
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s sslmode=disable dbname=%s",
				test.host, test.port, test.username, test.password, "postgres")
			db, err := connect(dsn)
			if err != nil {
				t.Errorf("Cannot connect to the db using %q: %s", dsn, err)
			}
			info, err := pginfo.NewWithLogger(db, nil, 30, logger)
			if err != nil {
				t.Errorf("Cannot run NewWithLogger using %q: %s", dsn, err)
			}
			errs := info.CollectGlobalInfo(db)
			if len(errs) > 0 {
				logger.Errorf("Cannot collect info")
				for _, err := range errs {
					logger.Error(err)
				}
				t.Errorf("Cannot collect global information using %q", dsn)
			}
		})
	}
}

func TestCollectPerDatabaseInfo(t *testing.T) {
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s sslmode=disable dbname=%s",
				test.host, test.port, test.username, test.password, "postgres")
			db, err := connect(dsn)
			if err != nil {
				t.Errorf("Cannot connect to the db using %q: %s", dsn, err)
			}
			info, err := pginfo.NewWithLogger(db, nil, 30, logger)
			if err != nil {
				t.Errorf("Cannot run New using %q: %s", dsn, err)
			}
			for _, dbName := range info.DatabaseNames() {
				dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s sslmode=disable dbname=%s",
					test.host, test.port, test.username, test.password, dbName)
				conn, err := connect(dsn)
				if err != nil {
					t.Errorf("Cannot connect to the %s database using %q: %s", dbName, dsn, err)
				}
				if err := info.CollectPerDatabaseInfo(conn, dbName); err != nil {
					t.Errorf("Cannot collect information for the %s database using %q: %s", dbName, dsn, err)
				}
				conn.Close()
			}
		})
	}
}
