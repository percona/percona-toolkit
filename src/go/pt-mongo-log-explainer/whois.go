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
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/collect"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/parser"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
	"github.com/pkg/errors"
	"github.com/rs/zerolog/log"
)

type whois struct {
	Search     string   `arg:"" name:"search" help:"the identifier (node name, ip, host:port, _id) to search"`
	SearchType string   `name:"type" help:"Kind of input: nodename, ip, hostport, _id. Auto-detected when possible." enum:"nodename,ip,hostport,_id,auto" default:"auto"`
	Paths      []string `arg:"" name:"paths" help:"paths of the log to use"`
	Json       bool
}

func (w *whois) Help() string {
	return fmt.Sprintf(`Resolve a hostname, host:port, IPv4, or member _id seen in mongod/mongos logs
into related names, addresses, replica sets, and ports discovered while scanning.

Usage:
  %[1]s whois 'mongo-rs0-0' *.log
  %[1]s whois '192.168.1.10' *.log
  %[1]s whois 'mongo-rs0-0:27017' --type hostport *.log
  %[1]s whois '0' --type _id *.log
`, toolname)
}

func (w *whois) Run() error {
	if w.SearchType == "auto" {
		detectAndNormalizeSearch(w)
	}

	// Phase 1: run the grep/regex pipeline to populate the translate DB.
	_, regexErr := timelineFromPaths(CLI.Whois.Paths, regex.AllRegexes())

	// Phase 2: run the structured parser pipeline to extract richer MongoDB identity.
	w.scanWithParser()

	if regexErr != nil && !translate.IsNodeNameKnown(w.Search) && !translate.IsNodeUUIDKnown(w.Search) && !translate.IsHostPortKnown(w.Search) {
		return errors.Wrap(regexErr, "found nothing to translate")
	}

	// Post-scan auto-detection for ambiguous 8-char inputs.
	if w.SearchType == "auto" {
		w.SearchType = resolveAmbiguous(w.Search)
		if w.SearchType == "" {
			return errors.New("could not detect the type of input. Try to provide --type. It may mean the info is unknown")
		}
	}

	if CLI.Verbosity == types.Debug {
		out, err := translate.DBToJson()
		if err != nil {
			return errors.Wrap(err, "could not dump translation structs to json")
		}
		fmt.Println(out)
	}

	log.Debug().Str("searchType", w.SearchType).Msg("whois searchType")

	out := translate.Whois(w.Search, w.SearchType)

	if w.Json {
		j, err := json.MarshalIndent(out, "", "\t")
		if err != nil {
			return err
		}
		fmt.Println(string(j))
	} else {
		fmt.Println(out)
	}
	return nil
}

func detectAndNormalizeSearch(w *whois) {
	switch {
	case regex.IsMongoObjectID(w.Search):
		w.Search = strings.ToLower(w.Search)
		w.SearchType = "_id"
	case regex.IsNodeUUID(w.Search):
		w.Search = utils.UUIDToShortUUID(w.Search)
		w.SearchType = "_id"
	case regex.IsNodeIP(w.Search):
		w.SearchType = "ip"
	case strings.Contains(w.Search, ":"):
		w.SearchType = "hostport"
	case len(w.Search) != 8:
		w.SearchType = "nodename"
	default:
		log.Info().Msg("input type is ambiguous; scanning files. Use --type to force nodename|ip|hostport|_id")
	}
}

func resolveAmbiguous(search string) string {
	if translate.IsNodeUUIDKnown(search) {
		return "_id"
	}
	if translate.IsNodeNameKnown(search) {
		return "nodename"
	}
	if translate.IsHostPortKnown(search) {
		return "hostport"
	}
	return ""
}

// scanWithParser runs the structured parser over every log file to populate the
// translate DB with MongoDB-specific identity (hostname, host:port, replica set).
func (w *whois) scanWithParser() {
	for _, path := range w.Paths {
		ctx := &parser.ScanContext{}
		var lastTS time.Time
		_ = collect.ForEachLine(path, CLI.GrepCmd, false, func(line string) error {
			ev := parser.ParseLine(path, line, ctx)
			if ev != nil && !ev.Time.IsZero() {
				lastTS = ev.Time
			}
			return nil
		})
		if lastTS.IsZero() {
			lastTS = time.Now()
		}
		ctx.FlushToTranslateDB(lastTS)
	}
}
