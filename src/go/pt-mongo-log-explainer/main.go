// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
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
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"time"

	"github.com/alecthomas/kong"
	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

const (
	toolname = "pt-mongo-log-explainer"
)

// We do not set anything here, these variables are defined by the Makefile
var (
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint
)

type CliOptions struct {
	config.ConfigFlag
	NoColor          bool
	Since            *time.Time      `help:"Only list events after this date, format: 2023-01-23T03:53:40Z (RFC3339)"`
	Until            *time.Time      `help:"Only list events before this date"`
	Verbosity        types.Verbosity `type:"counter" short:"v" default:"0" help:"-v: debug context (how the tool inferred hosts/ports), -vv: internal debug"`
	ExcludeRegexes   []string        `help:"Remove regexes from analysis. List regexes using 'pt-mongo-log-explainer regex-list'"`
	MergeByDirectory bool            `help:"Merge timelines by parent directory name instead of inferred node identity"`
	SkipMerge        bool            `help:"Do not merge log files; one column per file path"`

	Timeline  timeline  `cmd:"" help:"Structured chronological timeline (recommended for cluster analysis)"`
	List      list      `cmd:""`
	Whois     whois     `cmd:""`
	Summary   summary   `cmd:"" help:"Show cluster topology summary: nodes, IPs, versions, states"`
	Ctx       ctx       `cmd:""`
	RegexList regexList `cmd:""`

	GrepCmd string `help:"'grep' command path. Auto-detects 'ggrep' on macOS if available" default:"grep"`

	CustomRegexes map[string]string `help:"Add custom regexes, printed in magenta. Format: (golang regex string)=[optional static message to display]. If the static message is left empty, the captured string will be printed instead. Custom regexes are separated using semi-colon."`
	Version       kong.VersionFlag  `name:"version" help:"Show version and exit"`
	VersionCheck  bool              `name:"version-check" negatable:"" default:"false" help:"Contact Percona version-check API on startup (off by default for local builds; use --version-check to enable)"`
}

func (c *CliOptions) AfterApply() error {
	if c.VersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Error().Msgf("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Info().Msgf("%s", advice)
		}
	}

	return nil
}

var CLI = &CliOptions{}

func main() {
	kCtx, _, err := config.Setup(
		toolname,
		CLI,
		kong.Description("MongoDB cluster log analysis: structured timeline (timeline) or columnar list (list)"),
		kong.Vars{
			"version": fmt.Sprintf(
				"%s\nVersion %s\nBuild: %s using %s\nCommit: %s",
				toolname, Version, Build, GoVersion, Commit,
			),
		},
	)
	if err != nil {
		log.Error().Msgf("cannot get parameters: %s", err.Error())
		os.Exit(1)
	}

	if CLI.Version {
		return
	}

	if runtime.GOOS == "darwin" && CLI.GrepCmd == "grep" {
		if path, err := exec.LookPath("ggrep"); err == nil {
			CLI.GrepCmd = path
		}
	}

	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	zerolog.SetGlobalLevel(zerolog.InfoLevel)
	log.Logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr, NoColor: CLI.NoColor, FormatTimestamp: func(_ interface{}) string { return "" }})
	initComponentLogger()
	if CLI.Verbosity == types.Debug {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	}

	utils.SkipColor = CLI.NoColor

	err = regex.AddCustomRegexes(CLI.CustomRegexes)
	kCtx.FatalIfErrorf(err)

	err = kCtx.Run()
	kCtx.FatalIfErrorf(err)
}
