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
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/collect"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/correlator"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/parser"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/renderer"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/pkg/errors"
)

type timeline struct {
	Paths []string `arg:"" name:"paths" help:"MongoDB log files (text or JSON per line)"`

	FullScan bool `help:"Scan every line (slower; grep pre-filter misses rare lines without keywords)"`

	Elections     bool   `help:"Only election, primary/secondary transitions, heartbeats, topology"`
	Replication   bool   `help:"Only replication / initial sync / rollback / oplog"`
	Errors        bool   `help:"Only failures, auth, network, fatals"`
	Sharding      bool   `help:"Only chunk migration, balancer, sharding"`
	Performance   bool   `help:"Only slow queries / long ops"`
	JSON          bool   `help:"Emit JSON instead of human-readable lines"`
	Highlight     bool   `name:"highlight-anomalies" help:"Highlight anomaly tags in color (human output)"`
	SkipCorrelate bool   `help:"Skip sequence correlation hints"`
	SkipAnomalies bool   `help:"Skip anomaly tagging"`
	Timezone      string `help:"Normalize all timestamps to this timezone (e.g. UTC, America/New_York). Default: UTC" default:"UTC"`
	Limit         int    `help:"Maximum number of events to output (0 = unlimited)" default:"0"`
}

func (t *timeline) Help() string {
	return fmt.Sprintf(`Build a merged chronological timeline of MongoDB cluster events.

Output format (default):
  [timestamp] [node] [host:port] [event_type] [status] [details]

Examples:
  %[1]s timeline -- /data/mongo/*.log
  %[1]s timeline --full-scan --elections --replication /node1.log /node2.log
  %[1]s timeline --errors --highlight-anomalies=true *.log
  %[1]s timeline --json *.log
`, toolname)
}

func (t *timeline) Run() error {
	if len(t.Paths) == 0 {
		return errors.New("at least one log path is required")
	}

	loc, err := time.LoadLocation(t.Timezone)
	if err != nil {
		return errors.Wrapf(err, "invalid timezone %q", t.Timezone)
	}

	// Pre-allocate based on estimated event density (~1 event per 500 bytes).
	var totalSize int64
	for _, path := range t.Paths {
		if info, err := os.Stat(path); err == nil {
			totalSize += info.Size()
		}
	}
	estEvents := int(totalSize / 500)
	if estEvents < 256 {
		estEvents = 256
	}
	all := make([]*types.StructuredEvent, 0, estEvents)

	for _, path := range t.Paths {
		ctx := &parser.ScanContext{}
		err := collect.ForEachLine(path, CLI.GrepCmd, !t.FullScan, func(line string) error {
			ev := parser.ParseLine(path, line, ctx)
			if ev == nil {
				return nil
			}
			if CLI.Since != nil && ev.Time.Before(*CLI.Since) {
				return nil
			}
			if CLI.Until != nil && ev.Time.After(*CLI.Until) {
				return nil
			}
			ev.Time = ev.Time.In(loc)
			all = append(all, ev)
			return nil
		})
		if err != nil {
			return err
		}
	}

	if len(all) == 0 {
		return errors.New("no structured events found (try --full-scan or different log paths)")
	}

	correlator.SortByTime(all)
	if !t.SkipCorrelate {
		correlator.Correlate(all)
	}
	if !t.SkipAnomalies {
		correlator.MarkAnomalies(all)
	}

	out := renderer.FilterCategories(all, t.Elections, t.Replication, t.Errors, t.Sharding, t.Performance)
	if len(out) == 0 {
		return errors.New("no events after category filters (adjust flags or omit filters for full output)")
	}

	if t.Limit > 0 && len(out) > t.Limit {
		out = out[:t.Limit]
	}

	if t.JSON {
		return renderer.WriteJSON(os.Stdout, out)
	}
	return renderer.WriteHuman(os.Stdout, out, t.Highlight && !CLI.NoColor)
}
