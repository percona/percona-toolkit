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

package renderer

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
)

const humanTimeLayout = "2006-01-02 15:04:05"

// WriteHuman prints one line per event:
// [timestamp] [node] [host:port] [event_type] [status] [details]
// When utils.SkipColor is false, node names use a stable per-node color, event types use
// semantic colors (e.g. shutdown/stepdown/failures in red, healthy transitions in green).
func WriteHuman(w io.Writer, evts []*types.StructuredEvent, highlight bool) error {
	for _, e := range evts {
		ts := e.Time.Format(humanTimeLayout)
		if e.Time.IsZero() {
			ts = "unknown-time"
		}
		hp := e.HostPort
		if hp == "" {
			hp = "-"
		}
		node := e.Node
		if node == "" {
			node = "-"
		}
		line := formatHumanLine(e, ts, hp, node, highlight)
		if _, err := fmt.Fprintln(w, line); err != nil {
			return err
		}
	}
	return nil
}

// WriteJSON emits a JSON array of events.
func WriteJSON(w io.Writer, evts []*types.StructuredEvent) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(evts)
}

// FilterCategories keeps events matching enabled filters (OR). If none enabled, returns all.
func FilterCategories(evts []*types.StructuredEvent, elections, replication, errors_, sharding, performance bool) []*types.StructuredEvent {
	if !elections && !replication && !errors_ && !sharding && !performance {
		return evts
	}
	out := make([]*types.StructuredEvent, 0, len(evts))
	for _, e := range evts {
		if matchAnyFilter(e, elections, replication, errors_, sharding, performance) {
			out = append(out, e)
		}
	}
	return out
}

func matchAnyFilter(e *types.StructuredEvent, elections, replication, errors_, sharding, performance bool) bool {
	et := e.EventType
	cat := e.Category

	if elections && electionRelated(et, cat) {
		return true
	}
	if replication && replicationRelated(et, cat) {
		return true
	}
	if errors_ && failureRelated(e, et, cat) {
		return true
	}
	if sharding && shardingRelated(et, cat) {
		return true
	}
	if performance && performanceRelated(et, cat) {
		return true
	}
	return false
}

func electionRelated(et string, cat types.EventCategory) bool {
	if cat == types.CatRole || cat == types.CatTopology {
		return true
	}
	switch et {
	case "PRIMARY_TRANSITION", "STEPDOWN", "SECONDARY_TRANSITION", "MEMBER_STATE",
		"ELECTION", "ELECTION_SUCCESS", "ELECTION_FAIL",
		"RS_CONFIG", "HEARTBEAT", "HEARTBEAT_FAIL", "RS_INITIATE", "RECONFIG",
		"MEMBER_JOIN", "MEMBER_LEAVE", "MEMBER_UNREACHABLE",
		"QUORUM_LOSS", "QUORUM_OK":
		return true
	}
	if strings.HasPrefix(et, "ELECTION") {
		return true
	}
	return false
}

func replicationRelated(et string, cat types.EventCategory) bool {
	if cat == types.CatReplication {
		return true
	}
	switch et {
	case "INITIAL_SYNC", "ROLLBACK", "REPL_OPLOG", "REPL", "REPL_STATE", "REPL_LAG",
		"RS_INITIATE", "OPLOG_TAIL_SLOW", "SYNC_SOURCE_CHANGE", "OPLOG_WINDOW":
		return true
	}
	return false
}

func failureRelated(e *types.StructuredEvent, et string, cat types.EventCategory) bool {
	if cat == types.CatFailure {
		return true
	}
	if e.Status == types.StatusFailure {
		return true
	}
	switch et {
	case "NETWORK_ERROR", "AUTH_FAILURE", "FATAL_ERROR", "PROCESS_SHUTDOWN", "HEARTBEAT_FAIL",
		"CONN_POOL_ERROR", "SOCKET_ERROR", "DNS_ERROR", "WRITE_CONCERN_ERROR":
		return true
	}
	return false
}

func shardingRelated(et string, cat types.EventCategory) bool {
	if cat == types.CatSharding {
		return true
	}
	switch et {
	case "CHUNK_MIGRATION", "BALANCER", "SHARDING":
		return true
	}
	return false
}

func performanceRelated(et string, cat types.EventCategory) bool {
	if cat == types.CatPerformance {
		return true
	}
	switch et {
	case "LONG_RUNNING_CMD", "INDEX_BUILD", "OP_TIMEOUT", "CURSOR_TIMEOUT":
		return true
	}
	return strings.Contains(et, "SLOW")
}
