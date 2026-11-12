// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
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
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/oplog"
)

const (
	oplogHostCap   = 60
	oplogHostTail  = 20
	oplogLineWidth = 140
	oplogReasonCap = 200
	mib            = 1 << 20
)

type oplogSet struct {
	Name           string
	Primary        string
	LastElection   string
	ElectionReason string
	Members        []proto.OplogInfo
	Shortest       *proto.OplogInfo
	Longest        *proto.OplogInfo
	HostWidth      int
	StateWidth     int
}

func memberPhase(ctx context.Context, client *mongo.Client, co *options.ClientOptions, snap *snapshot, hi *hostInfo,
	b *budget, g *gaps,
) ([]proto.Members, []memberDetail, []proto.OplogInfo) {
	if hi.NodeType == "mongod" {
		return nil, nil, nil
	}

	ctx, cancel := b.ctx(ctx, memberPhaseBudget)
	defer cancel()

	members, err := oplog.Discover(ctx, client, snap.IsMaster, snap.IsMasterRaw, nodeCallTimeout)
	members = withSetRole(members, snap.clusterRole())
	if state := selfState(members); state != "" {
		g.setMemberState(state)
	}

	var (
		rows   []proto.OplogInfo
		walked []oplog.Member
	)
	if len(members) > 0 {
		rows, walked = oplog.GetOplogInfo(ctx, client, co, members, collectWorkers, nodeCallTimeout)
	}

	walked = withEntryFacts(walked, snap)
	setHostRole(hi, walked)

	instances, details, read, total := buildInstances(walked)
	needs := discoveryNeeds(snap)
	remoteArbiter := hi.IsArbiter && snap.ServerStatusErr != nil

	instancesErr := err
	if hi.IsArbiter && requiresAuth(err) && len(members) > 0 {
		logGap("Instances", err.Error(), true)
		instancesErr = nil
	}
	addInstancesGap(g, hi.IsArbiter, remoteArbiter, needs, instancesErr, instances, read, total)

	if err != nil && len(members) == 0 {
		g.add("Oplog", "Oplog", needs, err)
	}

	return instances, details, rows
}

func addInstancesGap(g *gaps, isArbiter, remoteArbiter bool, needs string, discoverErr error, instances []proto.Members,
	read, total int,
) {
	switch {
	case remoteArbiter && requiresAuth(discoverErr):
		logGap("Instances", discoverErr.Error(), true)
	case discoverErr != nil:
		g.add("Instances", "Instances", needs, discoverErr)
	case instances == nil:
		g.note("Instances", "Instances", "no members found", false)
	case read < total && remoteArbiter:
		logGap("Instances", fmt.Sprintf("partial: %d of %d members read", read, total), true)
	case read < total:
		g.note("Instances", "Instances", fmt.Sprintf("partial: %d of %d members read", read, total), isArbiter)
	}
}

func discoveryNeeds(snap *snapshot) string {
	if snap.isMongos() {
		return "getShardMap: clusterMonitor"
	}

	return "replSetGetStatus: clusterMonitor"
}

func selfState(members []oplog.Member) string {
	for _, m := range members {
		if m.Self {
			return m.State
		}
	}

	return ""
}

func oplogView(rows []proto.OplogInfo) any {
	return groupOplogInfo(rows)
}

func groupOplogInfo(rows []proto.OplogInfo) []oplogSet {
	var sets []oplogSet

	index := map[string]int{}
	for _, r := range rows {
		i, ok := index[r.ReplicaSet]
		if !ok {
			i = len(sets)
			index[r.ReplicaSet] = i
			sets = append(sets, oplogSet{Name: r.ReplicaSet})
		}
		sets[i].Members = append(sets[i].Members, r)
	}

	sort.Slice(sets, func(i, j int) bool { return sets[i].Name < sets[j].Name })

	for i := range sets {
		sets[i].summarize()
	}

	return sets
}

func (s *oplogSet) summarize() {
	sort.SliceStable(s.Members, func(i, j int) bool { return s.Members[i].Hostname < s.Members[j].Hostname })

	s.HostWidth, s.StateWidth = len("Host"), len("State")
	answered := false

	var windows []int
	for i, m := range s.Members {
		s.HostWidth = max(s.HostWidth, utf8.RuneCountInString(m.Hostname))
		s.StateWidth = max(s.StateWidth, utf8.RuneCountInString(m.State))
		answered = answered || !m.Now.IsZero()

		if m.HasData() && (m.State == "PRIMARY" || m.State == "SECONDARY") {
			windows = append(windows, i)
		}
	}

	s.HostWidth = min(s.HostWidth, oplogHostCap)
	s.Primary = setPrimary(s.Members, answered)
	s.LastElection, s.ElectionReason = lastElection(s.Members, s.Primary)

	if len(windows) < 2 {
		return
	}

	shortest, longest := windows[0], windows[0]
	for _, i := range windows[1:] {
		if s.Members[i].TimeDiffHours < s.Members[shortest].TimeDiffHours {
			shortest = i
		}
		if s.Members[i].TimeDiffHours >= s.Members[longest].TimeDiffHours {
			longest = i
		}
	}

	s.Shortest, s.Longest = &s.Members[shortest], &s.Members[longest]
}

func setPrimary(members []proto.OplogInfo, answered bool) string {
	for _, m := range members {
		if m.State == "PRIMARY" && m.Primary == m.Hostname {
			return m.Hostname
		}
	}

	for _, m := range members {
		if m.Primary != "" {
			return m.Primary
		}
	}

	for _, m := range members {
		if m.State == "PRIMARY" {
			return m.Hostname
		}
	}

	if answered {
		return "none"
	}

	return "unknown"
}

func lastElection(members []proto.OplogInfo, primary string) (string, string) {
	var latest time.Time

	for _, m := range members {
		if m.Primary != primary || m.ElectionTime.IsZero() {
			continue
		}

		if m.Hostname == primary {
			return formatTime(m.ElectionTime), m.ElectionReason
		}

		if m.ElectionTime.After(latest) {
			latest = m.ElectionTime
		}
	}

	return formatTime(latest), ""
}

func (s oplogSet) Lines() []string {
	maxW, usedW, pctW, winW := len("Max MB"), len("Used MB"), len("Used%"), len("Window")
	for _, m := range s.Members {
		if m.HasData() {
			maxW = max(maxW, len(strconv.FormatInt(m.MaxSizeMB, 10)))
			usedW = max(usedW, len(strconv.FormatInt(m.UsedMB, 10)))
			pctW = max(pctW, len(usedPct(m)))
			winW = max(winW, utf8.RuneCountInString(m.Running))
		}
	}

	lines := []string{fmt.Sprintf("  %-*s  %-*s  %*s  %*s  %*s  %*s  %s", s.HostWidth, "Host", s.StateWidth, "State",
		maxW, "Max MB", usedW, "Used MB", pctW, "Used%", winW, "Window", "Last Entry (UTC)")}

	for _, m := range s.Members {
		prefix := fmt.Sprintf("  %-*s  %-*s  ", s.HostWidth, cutMiddle(m.Hostname, s.HostWidth), s.StateWidth, m.State)

		if m.HasData() {
			lines = append(lines, prefix+fmt.Sprintf("%*d  %*d  %*s  %*s  %s", maxW, m.MaxSizeMB, usedW, m.UsedMB,
				pctW, usedPct(m), winW, m.Running, m.TLast.UTC().Format("2006-01-02 15:04:05")))

			continue
		}

		reason := m.Error
		if reason == "" {
			reason = "no data"
		}

		indent := utf8.RuneCountInString(prefix)
		for i, part := range wrapText(cutEnd(reason, oplogReasonCap), max(oplogLineWidth-indent, 20)) {
			if i > 0 {
				prefix = strings.Repeat(" ", indent)
			}
			lines = append(lines, prefix+part)
		}
	}

	return lines
}

func usedPct(m proto.OplogInfo) string {
	if m.MaxSizeMB <= 0 {
		return "-"
	}

	return formatPct(float64(m.Size) / float64(m.MaxSizeMB*mib) * 100)
}

func cutMiddle(s string, width int) string {
	r := []rune(s)
	if len(r) <= width {
		return s
	}

	tail := min(oplogHostTail, width/2)

	return string(r[:width-1-tail]) + "…" + string(r[len(r)-tail:])
}

func cutEnd(s string, width int) string {
	r := []rune(s)
	if len(r) <= width {
		return s
	}

	return string(r[:width-1]) + "…"
}

func wrapText(s string, width int) []string {
	var (
		lines []string
		line  []rune
	)

	for _, word := range strings.Fields(s) {
		w := []rune(word)

		for len(w) > width {
			if len(line) > 0 {
				lines = append(lines, string(line))
				line = nil
			}
			lines = append(lines, string(w[:width]))
			w = w[width:]
		}

		switch {
		case len(line) == 0:
			line = append([]rune(nil), w...)
		case len(line)+1+len(w) <= width:
			line = append(append(line, ' '), w...)
		default:
			lines = append(lines, string(line))
			line = append([]rune(nil), w...)
		}
	}

	if len(line) > 0 {
		lines = append(lines, string(line))
	}

	return lines
}
