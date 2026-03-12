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
	"database/sql"
	"fmt"
	"os"
	"strings"
	"text/template"

	"github.com/alecthomas/kong"
	"github.com/howeyc/gopass"
	_ "github.com/lib/pq"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/pginfo"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/templates"
)

const (
	toolname = "pt-pg-summary"
)

// We do not set anything here, these variables are defined by the Makefile
var (
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint
)

type connOpts struct {
	Host     string                    `name:"host" short:"h" help:"Host to connect to"`
	Port     int                       `name:"port" short:"p" help:"Port number to use for connection"`
	User     string                    `name:"username" short:"u" help:"User for login if not current user"`
	Password config.StdinRequestString `name:"passwrord" short:"W" help:"Password to use when connecting"`
	SSL      bool                      `name:"ssl" help:"Enable SSL for the connection" default:"false" negatable:""`
}

type cliOptions struct {
	config.ConfigFlag
	connOpts
	ReadSamples         string   `name:"read-samples" hidden:"" help:"Create a report from the files found in this directory"`
	SaveSamples         string   `name:"save-samples" hidden:"" help:"Save the data files used to generate the summary in this directory"`
	Databases           []string `name:"databases" help:"Summarize this comma-separated list of databases. All if not specified"`
	Seconds             int      `name:"sleep" help:"Seconds to sleep when gathering status counters" default:"10"`
	DefaultsFile        string   `name:"defaults-file" hidden:"" help:"Only read PostgreSQL options from the given file"`
	ListEncryptedTables bool     `name:"list-encrypted-tables" hidden:"" help:"Include a list of the encrypted tables in all databases"`
	LogLevel            string   `name:"log-level" short:"l" help:"Log level: panic, fatal, error, warn, info, debug." default:"warn"`
	config.VersionFlag
	config.VersionCheckFlag
}

func (c *cliOptions) AfterApply() error {
	err := c.connOpts.Password.Request(func() (string, error) {
		print("Password: ")
		pass, err := gopass.GetPasswd()
		return string(pass), err
	})
	if err != nil {
		return err
	}

	logLevel, err := log.ParseLevel(c.LogLevel)
	if err != nil {
		fmt.Printf("cannot set log level: %s", err.Error())
	}

	log.SetLevel(logLevel)

	if c.VersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Errorf("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Infof("%s", advice)
		}
	}

	return nil
}

func main() {
	var opts cliOptions
	kongCtx, _, err := config.Setup(
		toolname,
		&opts,
		kong.UsageOnError(),
		kong.Vars{
			"version": fmt.Sprintf(
				"%s\nVersion %s\nBuild: %s using %s\nCommit: %s",
				toolname, Version, Build, GoVersion, Commit,
			),
		},
	)
	if err != nil {
		log.Errorf("cannot get parameters: %s", err.Error())
		os.Exit(1)
	}

	if opts.Version {
		return
	}

	dsn := buildConnString(opts.connOpts, "postgres")
	logger := log.New()
	logger.Infof("Connecting to the database server using: %s", safeConnString(opts.connOpts, "postgres"))

	db, err := connect(dsn)
	if err != nil {
		logger.Errorf("Cannot connect to the database: %s\n", err)
		kongCtx.PrintUsage(true)
		os.Exit(1)
	}
	logger.Infof("Connection OK")

	info, err := pginfo.NewWithLogger(db, opts.Databases, opts.Seconds, logger)
	if err != nil {
		log.Fatalf("Cannot create a data collector instance: %s", err)
	}

	logger.Info("Getting global information")
	errs := info.CollectGlobalInfo(db)
	if len(errs) > 0 {
		logger.Errorf("Cannot collect info")
		for _, err := range errs {
			logger.Error(err)
		}
	}

	logger.Info("Collecting per database information")
	logger.Debugf("Will collect information for these databases: (%T), %v", info.DatabaseNames(), info.DatabaseNames())
	for _, dbName := range info.DatabaseNames() {
		dsn := buildConnString(opts.connOpts, dbName)
		logger.Infof("Connecting to the %q database", dbName)
		conn, err := connect(dsn)
		if err != nil {
			logger.Errorf("Cannot connect to the %s database: %s", dbName, err)
			continue
		}
		if err := info.CollectPerDatabaseInfo(conn, dbName); err != nil {
			logger.Errorf("Cannot collect information for the %s database: %s", dbName, err)
		}
		conn.Close()
	}

	masterTmpl, err := template.New("master").Funcs(funcsMap()).Parse(templates.TPL)
	if err != nil {
		log.Fatal(err)
	}

	if err := masterTmpl.ExecuteTemplate(os.Stdout, "report", info); err != nil {
		log.Fatal(err)
	}
}

func connect(dsn string) (*sql.DB, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, errors.Wrap(err, "cannot connect to the database")
	}

	if err := db.Ping(); err != nil {
		return nil, errors.Wrap(err, "cannot connect to the database")
	}
	return db, nil
}

func funcsMap() template.FuncMap {
	return template.FuncMap{
		"trim": func(size int, s string) string {
			if len(s) < size {
				return s
			}
			return s[:size] + "..."
		},
		"convertnullstring": func(s sql.NullString) string {
			if s.Valid {
				return s.String
			} else {
				return ""
			}
		},
		"convertnullint64": func(s sql.NullInt64) int64 {
			if s.Valid {
				return s.Int64
			} else {
				return 0
			}
		},
		"convertnullfloat64": func(s sql.NullFloat64) float64 {
			if s.Valid {
				return s.Float64
			} else {
				return 0.0
			}
		},
	}
}

func buildConnString(opts connOpts, dbName string) string {
	parts := []string{}
	if opts.Host != "" {
		parts = append(parts, fmt.Sprintf("host=%s", opts.Host))
	}
	if opts.Port != 0 {
		parts = append(parts, fmt.Sprintf("port=%d", opts.Port))
	}
	if opts.User != "" {
		parts = append(parts, fmt.Sprintf("user=%s", opts.User))
	}
	if opts.Password != "" {
		parts = append(parts, fmt.Sprintf("password=%s", opts.Password))
	}
	if opts.SSL {
		parts = append(parts, "sslmode=enable")
	} else {
		parts = append(parts, "sslmode=disable")
	}
	if dbName == "" {
		dbName = "postgres"
	}
	parts = append(parts, fmt.Sprintf("dbname=%s", dbName))

	return strings.Join(parts, " ")
}

// build the same connection string as buildConnString but the password is hidden so
// we can display this in the logs
func safeConnString(opts connOpts, dbName string) string {
	parts := []string{}
	if opts.Host != "" {
		parts = append(parts, fmt.Sprintf("host=%s", opts.Host))
	}
	if opts.Port != 0 {
		parts = append(parts, fmt.Sprintf("port=%d", opts.Port))
	}
	if opts.User != "" {
		parts = append(parts, fmt.Sprintf("user=%s", opts.User))
	}
	if opts.Password != "" {
		parts = append(parts, "password=******")
	}
	if opts.SSL {
		parts = append(parts, "sslmode=enable")
	} else {
		parts = append(parts, "sslmode=disable")
	}
	if dbName == "" {
		dbName = "postgres"
	}
	parts = append(parts, fmt.Sprintf("dbname=%s", dbName))

	return strings.Join(parts, " ")
}
