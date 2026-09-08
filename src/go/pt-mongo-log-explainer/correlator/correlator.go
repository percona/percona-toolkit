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

package correlator

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
)

var seqCounter int

func nextSeqID(prefix string) string {
	seqCounter++
	return fmt.Sprintf("%s-%d", prefix, seqCounter)
}

// ResetSequenceCounter resets the internal counter (useful for tests).
func ResetSequenceCounter() { seqCounter = 0 }

// addSeqTag prepends a "sequence=..." hint to an event's details, but only once.
// Without this guard an event matched by two upstream events (e.g. an election
// preceded by two stepdown lines) would receive the same tag repeatedly.
func addSeqTag(details, tag string) string {
	if strings.Contains(details, tag) {
		return details
	}
	return strings.TrimSpace(tag + " " + details)
}

// SortByTime sorts events chronologically (stable for equal timestamps).
func SortByTime(evts []*types.StructuredEvent) {
	sort.SliceStable(evts, func(i, j int) bool {
		if evts[i].Time.Equal(evts[j].Time) {
			return evts[i].SourceFile < evts[j].SourceFile
		}
		return evts[i].Time.Before(evts[j].Time)
	})
}

// Correlate adds cross-node sequence hints to event details and assigns SequenceIDs.
func Correlate(evts []*types.StructuredEvent) {
	correlateHeartbeatElection(evts)
	correlateStepdownChain(evts)
	correlateSyncLifecycle(evts)
	correlateMigrationLifecycle(evts)
	correlateRestartSequence(evts)
	correlateRollbackCascade(evts)
}

func correlateHeartbeatElection(evts []*types.StructuredEvent) {
	for i := range evts {
		if evts[i].EventType != "HEARTBEAT_FAIL" {
			continue
		}
		t0 := evts[i].Time
		for j := i + 1; j < len(evts); j++ {
			if evts[j].Time.Sub(t0) > 3*time.Minute {
				break
			}
			if strings.HasPrefix(evts[j].EventType, "ELECTION") {
				sid := nextSeqID("hb-elect")
				evts[i].SequenceID = sid
				evts[j].SequenceID = sid
				evts[j].Details = addSeqTag(evts[j].Details, "sequence=heartbeat_loss→election")
				break
			}
			if evts[j].EventType == "PRIMARY_TRANSITION" {
				sid := nextSeqID("hb-primary")
				evts[i].SequenceID = sid
				evts[j].SequenceID = sid
				evts[j].Details = addSeqTag(evts[j].Details, "sequence=heartbeat_loss→primary_change")
				break
			}
		}
	}
}

// correlateStepdownChain: STEPDOWN -> ELECTION -> PRIMARY_TRANSITION within 30s
func correlateStepdownChain(evts []*types.StructuredEvent) {
	for i := range evts {
		if evts[i].EventType != "STEPDOWN" {
			continue
		}
		t0 := evts[i].Time
		sid := ""
		for j := i + 1; j < len(evts); j++ {
			if evts[j].Time.Sub(t0) > 30*time.Second {
				break
			}
			if strings.HasPrefix(evts[j].EventType, "ELECTION") && sid == "" {
				sid = nextSeqID("stepdown")
				evts[i].SequenceID = sid
				evts[j].SequenceID = sid
				evts[j].Details = addSeqTag(evts[j].Details, "sequence=stepdown→election")
			}
			if evts[j].EventType == "PRIMARY_TRANSITION" && sid != "" {
				evts[j].SequenceID = sid
				evts[j].Details = addSeqTag(evts[j].Details, "sequence=stepdown→election→primary")
				break
			}
		}
	}
}

// correlateSyncLifecycle: INITIAL_SYNC start -> complete/fail on same node
func correlateSyncLifecycle(evts []*types.StructuredEvent) {
	for i := range evts {
		if evts[i].EventType != "INITIAL_SYNC" || evts[i].Status != types.StatusInfo {
			continue
		}
		t0 := evts[i].Time
		node := evts[i].Node
		for j := i + 1; j < len(evts); j++ {
			if evts[j].Time.Sub(t0) > 2*time.Hour {
				break
			}
			if evts[j].EventType == "INITIAL_SYNC" && evts[j].Node == node &&
				(evts[j].Status == types.StatusSuccess || evts[j].Status == types.StatusFailure) {
				sid := nextSeqID("isync")
				evts[i].SequenceID = sid
				evts[j].SequenceID = sid
				tag := "sequence=initial_sync_lifecycle"
				evts[i].Details = addSeqTag(evts[i].Details, tag)
				evts[j].Details = addSeqTag(evts[j].Details, tag)
				break
			}
		}
	}
}

// correlateMigrationLifecycle: CHUNK_MIGRATION start -> complete/fail
func correlateMigrationLifecycle(evts []*types.StructuredEvent) {
	for i := range evts {
		if evts[i].EventType != "CHUNK_MIGRATION" || !strings.Contains(evts[i].Details, "phase=start") {
			continue
		}
		t0 := evts[i].Time
		for j := i + 1; j < len(evts); j++ {
			if evts[j].Time.Sub(t0) > 30*time.Minute {
				break
			}
			if evts[j].EventType == "CHUNK_MIGRATION" &&
				(strings.Contains(evts[j].Details, "phase=complete") || strings.Contains(evts[j].Details, "phase=abort")) {
				sid := nextSeqID("migrate")
				evts[i].SequenceID = sid
				evts[j].SequenceID = sid
				break
			}
		}
	}
}

// correlateRestartSequence: PROCESS_SHUTDOWN -> PROCESS_START on same node
func correlateRestartSequence(evts []*types.StructuredEvent) {
	for i := range evts {
		if evts[i].EventType != "PROCESS_SHUTDOWN" {
			continue
		}
		t0 := evts[i].Time
		node := evts[i].Node
		for j := i + 1; j < len(evts); j++ {
			if evts[j].Time.Sub(t0) > 10*time.Minute {
				break
			}
			if evts[j].EventType == "PROCESS_START" && evts[j].Node == node {
				sid := nextSeqID("restart")
				evts[i].SequenceID = sid
				evts[j].SequenceID = sid
				evts[j].Details = addSeqTag(evts[j].Details, "sequence=restart")
				break
			}
		}
	}
}

// correlateRollbackCascade: ROLLBACK -> INITIAL_SYNC or catch-up replication on same node
func correlateRollbackCascade(evts []*types.StructuredEvent) {
	for i := range evts {
		if evts[i].EventType != "ROLLBACK" {
			continue
		}
		t0 := evts[i].Time
		node := evts[i].Node
		for j := i + 1; j < len(evts); j++ {
			if evts[j].Time.Sub(t0) > 10*time.Minute {
				break
			}
			if evts[j].Node == node &&
				(evts[j].EventType == "INITIAL_SYNC" || evts[j].EventType == "REPL_OPLOG") {
				sid := nextSeqID("rollback")
				evts[i].SequenceID = sid
				evts[j].SequenceID = sid
				evts[j].Details = addSeqTag(evts[j].Details, "sequence=rollback→recovery")
				break
			}
		}
	}
}

// MarkAnomalies sets the Anomaly field using heuristic rules.
func MarkAnomalies(evts []*types.StructuredEvent) {
	for i := range evts {
		markRollback(evts, i)
		markLag(evts, i)
		markElectionStorm(evts, i)
		markFrequentElections(evts, i)
		markTopologyFlap(evts, i)
		markNodeFlapping(evts, i)
		markSyncFailure(evts, i)
		markAuthBurst(evts, i)
		markSustainedHeartbeatFail(evts, i)
		markSyncTimeout(evts, i)
	}
}

func markRollback(evts []*types.StructuredEvent, i int) {
	if evts[i].EventType == "ROLLBACK" {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "ROLLBACK")
	}
}

var reLagNum = regexp.MustCompile(`lag=([0-9]+(?:\.[0-9]+)?)`)

func markLag(evts []*types.StructuredEvent, i int) {
	det := strings.ToLower(evts[i].Details)
	if evts[i].EventType == "REPL_LAG" || strings.Contains(det, "lag") {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "LAG")
		if m := reLagNum.FindStringSubmatch(evts[i].Details); len(m) > 1 {
			if v, err := strconv.ParseFloat(m[1], 64); err == nil && v > 10 {
				evts[i].Anomaly = appendTag(evts[i].Anomaly, "LAG_SPIKE")
			}
		}
	}
}

// 3+ elections in 5 minutes
func markElectionStorm(evts []*types.StructuredEvent, i int) {
	if !strings.HasPrefix(evts[i].EventType, "ELECTION") {
		return
	}
	n := countInWindow(evts, i, func(e *types.StructuredEvent) bool {
		return strings.HasPrefix(e.EventType, "ELECTION")
	}, 5*time.Minute)
	if n >= 3 {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "ELECTION_STORM")
	}
}

// 4+ elections in 15 minutes (original rule preserved)
func markFrequentElections(evts []*types.StructuredEvent, i int) {
	if !strings.HasPrefix(evts[i].EventType, "ELECTION") {
		return
	}
	n := countInWindow(evts, i, func(e *types.StructuredEvent) bool {
		return strings.HasPrefix(e.EventType, "ELECTION")
	}, 15*time.Minute)
	if n >= 4 {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "FREQUENT_ELECTIONS")
	}
}

func markTopologyFlap(evts []*types.StructuredEvent, i int) {
	if evts[i].EventType != "MEMBER_LEAVE" && evts[i].EventType != "MEMBER_JOIN" {
		return
	}
	n := countInWindow(evts, i, func(e *types.StructuredEvent) bool {
		return e.EventType == "MEMBER_LEAVE" || e.EventType == "MEMBER_JOIN"
	}, 30*time.Minute)
	if n >= 5 {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "TOPOLOGY_FLAP")
	}
}

// Per-node PROCESS_SHUTDOWN -> PROCESS_START cycles: 3+ restarts in 30 min
func markNodeFlapping(evts []*types.StructuredEvent, i int) {
	if evts[i].EventType != "PROCESS_START" {
		return
	}
	node := evts[i].Node
	n := countInWindow(evts, i, func(e *types.StructuredEvent) bool {
		return e.Node == node && (e.EventType == "PROCESS_START" || e.EventType == "PROCESS_SHUTDOWN")
	}, 30*time.Minute)
	if n >= 6 { // 3 restart cycles = 3 shutdowns + 3 starts
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "NODE_FLAPPING")
	}
}

func markSyncFailure(evts []*types.StructuredEvent, i int) {
	if evts[i].Status == types.StatusFailure && strings.Contains(evts[i].EventType, "SYNC") {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "SYNC_FAILURE")
	}
}

// 5+ AUTH_FAILURE from same node within 1 minute
func markAuthBurst(evts []*types.StructuredEvent, i int) {
	if evts[i].EventType != "AUTH_FAILURE" {
		return
	}
	node := evts[i].Node
	n := countInWindow(evts, i, func(e *types.StructuredEvent) bool {
		return e.EventType == "AUTH_FAILURE" && e.Node == node
	}, 1*time.Minute)
	if n >= 5 {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "AUTH_BURST")
	}
}

// 3+ HEARTBEAT_FAIL within 30 seconds
func markSustainedHeartbeatFail(evts []*types.StructuredEvent, i int) {
	if evts[i].EventType != "HEARTBEAT_FAIL" {
		return
	}
	n := countInWindow(evts, i, func(e *types.StructuredEvent) bool {
		return e.EventType == "HEARTBEAT_FAIL"
	}, 30*time.Second)
	if n >= 3 {
		evts[i].Anomaly = appendTag(evts[i].Anomaly, "SUSTAINED_HB_FAIL")
	}
}

// INITIAL_SYNC start without complete within 2 hours on same node
func markSyncTimeout(evts []*types.StructuredEvent, i int) {
	if evts[i].EventType != "INITIAL_SYNC" || evts[i].Status != types.StatusInfo {
		return
	}
	node := evts[i].Node
	t0 := evts[i].Time
	for j := i + 1; j < len(evts); j++ {
		if evts[j].Time.Sub(t0) > 2*time.Hour {
			evts[i].Anomaly = appendTag(evts[i].Anomaly, "SYNC_TIMEOUT")
			return
		}
		if evts[j].EventType == "INITIAL_SYNC" && evts[j].Node == node &&
			(evts[j].Status == types.StatusSuccess || evts[j].Status == types.StatusFailure) {
			return
		}
	}
	// Reached end of events without finding completion
	evts[i].Anomaly = appendTag(evts[i].Anomaly, "SYNC_TIMEOUT")
}

// countInWindow counts matching events within a time window around the given index.
// Exploits the sorted order of evts to break early.
func countInWindow(evts []*types.StructuredEvent, idx int, pred func(*types.StructuredEvent) bool, win time.Duration) int {
	t0 := evts[idx].Time
	c := 0
	// scan backwards
	for j := idx; j >= 0; j-- {
		if t0.Sub(evts[j].Time) > win {
			break
		}
		if pred(evts[j]) {
			c++
		}
	}
	// scan forwards (skip idx to avoid double-count)
	for j := idx + 1; j < len(evts); j++ {
		if evts[j].Time.Sub(t0) > win {
			break
		}
		if pred(evts[j]) {
			c++
		}
	}
	return c
}

func appendTag(cur, tag string) string {
	if strings.Contains(cur, tag) {
		return cur
	}
	if cur == "" {
		return tag
	}
	return cur + "," + tag
}
