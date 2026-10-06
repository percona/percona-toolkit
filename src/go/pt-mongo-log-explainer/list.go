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

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/display"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/pkg/errors"
)

type list struct {
	// Paths is duplicated because it could not work as variadic with kong cli if I set it as CLI object
	Paths                  []string `arg:"" name:"paths" help:"paths of the log to use"`
	SkipStateColoredColumn bool     `help:"Do not color idle columns by inferred replica-set member state"`
	All                    bool     `help:"List everything" xor:"states,topology,events,replication,cluster"`
	States                 bool     `help:"List replica-set member state changes (PRIMARY, SECONDARY, ...)" xor:"states"`
	Topology               bool     `help:"List topology / config events (initiate, reconfig, member add/remove)" xor:"topology"`
	Events                 bool     `help:"List process events (startup, shutdown, fatal errors)" xor:"events"`
	Replication            bool     `help:"List replication sync events (initial sync, oplog apply, resync)" xor:"replication"`
	Cluster                bool     `help:"List cluster-level events (elections, not-primary, write concern, stepdown, rollback)" xor:"cluster"`
}

func (l *list) Help() string {
	return fmt.Sprintf(`List events for each node in a columnar output
	It will merge logs between themselves

	"identifier" is an internal metadata, this is used to merge logs.

Usage:
	%[1]s list --all <list of files>
	%[1]s list --all *.log
	%[1]s list --replication --topology --states <list of files>
	%[1]s list --events --topology *.log
	`, toolname)
}

func (l *list) Run() error {

	if !(l.All || l.Events || l.States || l.Replication || l.Topology || l.Cluster) {
		return errors.New("flag required: --all, or any parameters from: --replication --topology --events --states --cluster")
	}

	toCheck := l.regexesToUse()

	timeline, err := timelineFromPaths(CLI.List.Paths, toCheck)
	if err != nil {
		return errors.Wrap(err, "could not list events")
	}

	if CLI.Verbosity == types.Debug {
		out, err := translate.DBToJson()
		if err != nil {
			return errors.Wrap(err, "could not dump translation structs to json")
		}
		fmt.Println(out)
	}

	display.TimelineCLI(timeline, CLI.Verbosity)

	return nil
}

func (l *list) regexesToUse() types.RegexMap {

	toCheck := regex.IdentsMap
	if l.States || l.All {
		toCheck.Merge(regex.StatesMap)
	} else if !l.SkipStateColoredColumn {
		regex.SetVerbosity(types.DebugContext, regex.StatesMap)
		toCheck.Merge(regex.StatesMap)
	}
	if l.Topology || l.All {
		toCheck.Merge(regex.TopologyMap)
	}
	if l.Replication || l.All {
		toCheck.Merge(regex.ReplicationMap)
	}
	if l.Cluster || l.All {
		toCheck.Merge(regex.ClusterMap)
	}
	if l.Events || l.All {
		toCheck.Merge(regex.EventsMap)
	} else if !l.SkipStateColoredColumn {
		regex.SetVerbosity(types.DebugContext, regex.EventsMap)
		toCheck.Merge(regex.EventsMap)
	}
	toCheck.Merge(regex.CustomMap)
	return toCheck
}
