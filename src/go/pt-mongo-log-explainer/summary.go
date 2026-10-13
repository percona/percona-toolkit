// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.

package main

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/collect"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/parser"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
	"github.com/pkg/errors"
)

type summary struct {
	Paths []string `arg:"" name:"paths" help:"MongoDB log files to analyze"`
}

func (s *summary) Help() string {
	return fmt.Sprintf(`Show cluster topology summary: each node's hostname, IP, host:port,
replica set, MongoDB version, and last known member state.

Usage:
  %[1]s summary *.log
  %[1]s summary tests/logs/replicaset/*.log
`, toolname)
}

type nodeSummary struct {
	Hostname string
	IP       string
	HostPort string
	RSName   string
	Version  string
	State    string
	LogFile  string
}

func (s *summary) Run() error {
	if len(s.Paths) == 0 {
		return errors.New("at least one log path is required")
	}

	nodes := s.collectNodes()
	if len(nodes) == 0 {
		return errors.New("no node identity found in the provided logs")
	}

	sort.Slice(nodes, func(i, j int) bool {
		if nodes[i].RSName != nodes[j].RSName {
			return nodes[i].RSName < nodes[j].RSName
		}
		return nodes[i].Hostname < nodes[j].Hostname
	})

	s.printSummary(nodes)
	return nil
}

func (s *summary) collectNodes() []nodeSummary {
	seen := map[string]*nodeSummary{} // keyed by hostname+hostport
	var order []string                // preserves first-seen order

	for _, path := range s.Paths {
		ctx := &parser.ScanContext{}
		lastState := ""
		var lastTS time.Time

		_ = collect.ForEachLine(path, CLI.GrepCmd, false, func(line string) error {
			ev := parser.ParseLine(path, line, ctx)
			if ev == nil {
				return nil
			}
			if !ev.Time.IsZero() {
				lastTS = ev.Time
			}
			st := extractState(ev)
			if st != "" {
				lastState = st
			}
			return nil
		})

		hostname := ctx.NodeLabel()
		if hostname == "" || hostname == "unknown" {
			continue
		}

		if lastTS.IsZero() {
			lastTS = time.Now()
		}
		ctx.FlushToTranslateDB(lastTS)

		// Fall back: if structured parser didn't catch state, try regex pipeline.
		if lastState == "" {
			lastState = s.stateFromRegex(path)
		}

		hp := ctx.HostPort()
		key := hostname
		if hp != "" {
			key = hp
		}
		if existing, ok := seen[key]; ok {
			if lastState != "" {
				existing.State = lastState
			}
			if ctx.ServerIP != "" {
				existing.IP = ctx.ServerIP
			}
			if hp != "" && existing.HostPort == "" {
				existing.HostPort = hp
			}
			if ctx.Version != "" {
				existing.Version = ctx.Version
			}
			if ctx.RSName != "" {
				existing.RSName = ctx.RSName
			}
			continue
		}

		ns := &nodeSummary{
			Hostname: hostname,
			IP:       ctx.ServerIP,
			HostPort: hp,
			RSName:   ctx.RSName,
			Version:  ctx.Version,
			State:    lastState,
			LogFile:  path,
		}
		seen[key] = ns
		order = append(order, key)
	}

	nodes := make([]nodeSummary, 0, len(order))
	for _, key := range order {
		nodes = append(nodes, *seen[key])
	}
	return nodes
}

func extractState(ev *types.StructuredEvent) string {
	switch ev.EventType {
	case "PRIMARY_TRANSITION":
		return "PRIMARY"
	case "STEPDOWN":
		return "SECONDARY"
	case "SECONDARY_TRANSITION":
		return "SECONDARY"
	case "MEMBER_STATE":
		if strings.HasPrefix(ev.Details, "state=") {
			return strings.TrimPrefix(ev.Details, "state=")
		}
		for _, kw := range []string{"PRIMARY", "SECONDARY", "ARBITER", "RECOVERING", "STARTUP", "STARTUP2", "ROLLBACK", "DOWN", "REMOVED"} {
			if strings.Contains(strings.ToUpper(ev.Details), kw) {
				return kw
			}
		}
	}
	return ""
}

func (s *summary) stateFromRegex(path string) string {
	regexes := make(types.RegexMap, len(regex.IdentsMap)+len(regex.StatesMap))
	regexes.Merge(regex.IdentsMap)
	regexes.Merge(regex.StatesMap)
	timeline, err := timelineFromPaths([]string{path}, regexes)
	if err != nil {
		return ""
	}
	ctxs := timeline.GetLatestContextsByNodes()
	for _, logCtx := range ctxs {
		if st := logCtx.State(); st != "" {
			return st
		}
	}
	return ""
}

func (s *summary) printSummary(nodes []nodeSummary) {
	currentRS := ""

	for i, n := range nodes {
		if n.RSName != currentRS {
			if i > 0 {
				fmt.Println()
			}
			rs := n.RSName
			if rs == "" {
				rs = "(no replica set)"
			}
			fmt.Println(utils.Paint(utils.BrightWhiteText, "Replica Set: "+rs))
			fmt.Println(utils.Paint(utils.BrightWhiteText, strings.Repeat("─", 50)))
			currentRS = n.RSName
		}

		color := nodeColor(i)

		hostname := utils.Paint(color, n.Hostname)
		ip := n.IP
		if ip == "" {
			ip = "-"
		}
		hp := n.HostPort
		if hp == "" {
			hp = "-"
		}
		version := n.Version
		if version == "" {
			version = "-"
		}
		state := n.State
		if state == "" {
			state = "UNKNOWN"
		}
		stateDisplay := utils.PaintForState(state, state)

		fmt.Printf("  %s\n", hostname)
		fmt.Printf("    %-12s %s\n", utils.Paint(utils.BlueText, "IP:"), ip)
		fmt.Printf("    %-12s %s\n", utils.Paint(utils.BlueText, "Host:Port:"), hp)
		fmt.Printf("    %-12s %s\n", utils.Paint(utils.BlueText, "Version:"), version)
		fmt.Printf("    %-12s %s\n", utils.Paint(utils.BlueText, "State:"), stateDisplay)
	}
}

var memberColors = []utils.Color{
	utils.BrightCyanText,
	utils.BrightMagentaText,
	utils.BrightGreenText,
	utils.BrightYellowText,
	utils.BrightBlueText,
	utils.BrightWhiteText,
}

func nodeColor(idx int) utils.Color {
	return memberColors[idx%len(memberColors)]
}
