package main

import (
	"fmt"
	"os"
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/internal/tu"
)

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}

func TestConnection(t *testing.T) {
	tests := []struct {
		name     string
		host     string
		port     string
		username string
		password string
	}{
		{"IPv4PG9", tu.IPv4Host, tu.IPv4PG9Port, tu.Username, tu.Password},
		{"IPv4PG10", tu.IPv4Host, tu.IPv4PG10Port, tu.Username, tu.Password},
		{"IPv4PG11", tu.IPv4Host, tu.IPv4PG11Port, tu.Username, tu.Password},
		{"IPv4PG12", tu.IPv4Host, tu.IPv4PG12Port, tu.Username, tu.Password},
		// use IPV6 for PostgreSQL 9
		//{"IPV6", tu.IPv6Host, tu.IPv6PG9Port, tu.Username, tu.Password},
		// use an "external" IP to simulate a remote host
		{"remote_host", tu.PG9DockerIP, tu.DefaultPGPort, tu.Username, tu.Password},
	}

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
