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

package parser

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/regex"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
)

var reSlowMS = regexp.MustCompile(`(?i)([0-9]{3,})ms\s*$`)
var reElectionWord = regexp.MustCompile(`(?i)\belection\b`)
var reMemberStateLine = regexp.MustCompile(`(?i)Replica Set Member State:\s*([A-Z0-9_]+)`)

func textHasElectionNoise(low string) bool {
	return strings.Contains(low, "electiontimeout") || strings.Contains(low, "electiontimeoutmillis")
}

func textMentionsRealElection(low string) bool {
	if textHasElectionNoise(low) {
		return false
	}
	return reElectionWord.MatchString(low)
}

func jsonMentionsRealElection(lm string) bool {
	if strings.Contains(lm, "electiontimeout") || strings.Contains(lm, "electiontimeoutmillis") {
		return false
	}
	if strings.Contains(lm, "election") && strings.Contains(lm, "succeed") {
		return true
	}
	if strings.Contains(lm, "election") && (strings.Contains(lm, "fail") || strings.Contains(lm, "abort")) {
		return true
	}
	return reElectionWord.MatchString(lm)
}

func isOplogReplicationLine(low string) bool {
	return strings.Contains(low, "oplog.rs") || strings.Contains(low, "local.oplog")
}

// IsJSONLine returns true if the line looks like a MongoDB structured JSON log record.
func IsJSONLine(line string) bool {
	s := strings.TrimSpace(line)
	return len(s) > 1 && s[0] == '{' && s[len(s)-1] == '}'
}

// ParseLine turns one log line into a structured event when it matches known patterns.
func ParseLine(path, line string, ctx *ScanContext) *types.StructuredEvent {
	line = strings.TrimSpace(line)
	if line == "" {
		return nil
	}
	if ctx.SourcePath == "" {
		ctx.SourcePath = path
	}
	if IsJSONLine(line) {
		return parseJSONLine(path, line, ctx)
	}
	ctx.UpdateFromText(line)
	return parseTextLine(path, line, ctx)
}

func parseJSONLine(path, line string, ctx *ScanContext) *types.StructuredEvent {
	var root map[string]interface{}
	if err := json.Unmarshal([]byte(line), &root); err != nil {
		return nil
	}
	ts := extractJSONTime(root)
	if ts.IsZero() {
		if t, _, ok := regex.SearchDateFromLog(line); ok {
			ts = t
		}
	}
	if ts.IsZero() {
		return nil
	}
	msg, _ := root["msg"].(string)
	c, _ := root["c"].(string)
	attr, _ := root["attr"].(map[string]interface{})
	ctx.UpdateFromJSONAttr(attr, msg, c)

	et, cat, st, details := classifyJSON(msg, c, attr, line)
	if et == "" {
		return nil
	}
	return finalizeEvent(path, line, ctx, ts, et, cat, st, details)
}

func extractJSONTime(root map[string]interface{}) time.Time {
	tv, ok := root["t"]
	if !ok {
		return time.Time{}
	}
	switch t := tv.(type) {
	case map[string]interface{}:
		if d, ok := t["$date"].(string); ok {
			for _, layout := range regex.DateLayouts {
				if tt, err := time.Parse(layout, d); err == nil {
					return tt
				}
			}
			if tt, err := time.Parse(time.RFC3339Nano, d); err == nil {
				return tt
			}
			if tt, err := time.Parse(time.RFC3339, d); err == nil {
				return tt
			}
		}
		if nested, ok := t["$date"].(map[string]interface{}); ok {
			if nl, ok := nested["$numberLong"].(string); ok {
				if ms, err := strconv.ParseInt(nl, 10, 64); err == nil {
					return time.UnixMilli(ms).UTC()
				}
			}
		}
	case string:
		if tt, err := time.Parse(time.RFC3339Nano, t); err == nil {
			return tt
		}
	}
	return time.Time{}
}

func classifyJSON(msg, c string, attr map[string]interface{}, raw string) (eventType string, category types.EventCategory, status types.EventStatus, details string) {
	lm := strings.ToLower(msg)
	lc := strings.ToLower(c)

	switch {
	case strings.Contains(lm, "waiting for connections"):
		return "NODE_LISTEN", types.CatNode, types.StatusInfo, msg
	case strings.Contains(lm, "mongod startup") || strings.Contains(lm, "mongos startup"):
		return "PROCESS_START", types.CatNode, types.StatusSuccess, msg
	case strings.Contains(lm, "shutting down") || strings.Contains(lm, "now exiting"):
		return "PROCESS_SHUTDOWN", types.CatFailure, types.StatusWarn, msg
	case strings.Contains(lm, "transition to primary"):
		return "PRIMARY_TRANSITION", types.CatRole, types.StatusSuccess, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "stepped down") || strings.Contains(lm, "stepping down"):
		return "STEPDOWN", types.CatRole, types.StatusWarn, jsonAttrSummary(attr, msg)
	case jsonMentionsRealElection(lm) && strings.Contains(lm, "succeed"):
		return "ELECTION_SUCCESS", types.CatRole, types.StatusSuccess, jsonAttrSummary(attr, msg)
	case jsonMentionsRealElection(lm) && (strings.Contains(lm, "fail") || strings.Contains(lm, "abort")):
		return "ELECTION_FAIL", types.CatRole, types.StatusFailure, jsonAttrSummary(attr, msg)
	case jsonMentionsRealElection(lm):
		return "ELECTION", types.CatRole, types.StatusInfo, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "rollback") || strings.Contains(lm, "rolling back"):
		return "ROLLBACK", types.CatReplication, types.StatusFailure, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "initial sync"):
		st := types.StatusInfo
		if strings.Contains(lm, "fail") || strings.Contains(lm, "error") {
			st = types.StatusFailure
		}
		if strings.Contains(lm, "complete") || strings.Contains(lm, "finished") {
			st = types.StatusSuccess
		}
		return "INITIAL_SYNC", types.CatReplication, st, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "heartbeat") && (strings.Contains(lm, "fail") || strings.Contains(lm, "timeout") || strings.Contains(lm, "error")):
		return "HEARTBEAT_FAIL", types.CatTopology, types.StatusFailure, msg
	case strings.Contains(lm, "heartbeat"):
		return "HEARTBEAT", types.CatTopology, types.StatusInfo, msg
	case strings.Contains(lm, "member is now in state"):
		return "MEMBER_STATE", types.CatRole, types.StatusInfo, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "member") && (strings.Contains(lm, "added") || strings.Contains(lm, "join")):
		return "MEMBER_JOIN", types.CatTopology, types.StatusSuccess, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "member") && (strings.Contains(lm, "removed") || strings.Contains(lm, "left")):
		return "MEMBER_LEAVE", types.CatTopology, types.StatusWarn, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "replset") && strings.Contains(lm, "reconfig"):
		return "RECONFIG", types.CatTopology, types.StatusInfo, msg

	// --- Replication: sync source changes and oplog ---
	case strings.Contains(lm, "changed sync source") || strings.Contains(lm, "sync source"):
		return "SYNC_SOURCE_CHANGE", types.CatReplication, types.StatusInfo, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "oplog window"):
		return "OPLOG_WINDOW", types.CatReplication, types.StatusWarn, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "repl writer") || (isOplogReplicationLine(lm) && strings.Contains(lm, "applied")):
		return "REPL_OPLOG", types.CatReplication, types.StatusInfo, shorten(msg, 160)
	case attr != nil && (attr["lag"] != nil || attr["replicationLag"] != nil):
		return "REPL_LAG", types.CatReplication, types.StatusWarn, jsonLagSummary(attr, msg)

	// --- Topology: quorum ---
	case strings.Contains(lm, "not enough") && strings.Contains(lm, "majority"):
		return "QUORUM_LOSS", types.CatTopology, types.StatusFailure, msg
	case strings.Contains(lm, "quorum check") && strings.Contains(lm, "succeeded"):
		return "QUORUM_OK", types.CatTopology, types.StatusSuccess, msg

	// --- Topology: member unreachable ---
	case strings.Contains(lm, "not reachable") || (strings.Contains(lm, "member") && strings.Contains(lm, "down")):
		return "MEMBER_UNREACHABLE", types.CatTopology, types.StatusFailure, jsonAttrSummary(attr, msg)

	// --- Sharding: specific migration lifecycle (must precede generic chunk/balancer cases) ---
	case strings.Contains(lm, "migration started"):
		return "CHUNK_MIGRATION", types.CatSharding, types.StatusInfo, "phase=start " + jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "migration committed"):
		return "CHUNK_MIGRATION", types.CatSharding, types.StatusSuccess, "phase=complete " + jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "migration aborted"):
		return "CHUNK_MIGRATION", types.CatSharding, types.StatusFailure, "phase=abort " + jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "balancer enabled"):
		return "BALANCER", types.CatSharding, types.StatusSuccess, "action=enabled"
	case strings.Contains(lm, "balancer disabled"):
		return "BALANCER", types.CatSharding, types.StatusWarn, "action=disabled"
	case strings.Contains(lm, "balancer round"):
		return "BALANCER", types.CatSharding, types.StatusInfo, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "chunk") && (strings.Contains(lm, "move") || strings.Contains(lm, "migration")):
		return "CHUNK_MIGRATION", types.CatSharding, types.StatusInfo, jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "balancer"):
		return "BALANCER", types.CatSharding, types.StatusInfo, msg

	// --- Failures: specific checks before generic NETWORK_ERROR ---
	case strings.Contains(lm, "dns resolution") || strings.Contains(lm, "dns lookup"):
		return "DNS_ERROR", types.CatFailure, types.StatusFailure, shorten(msg, 200)
	case strings.Contains(lm, "connection pool"):
		return "CONN_POOL_ERROR", types.CatFailure, types.StatusFailure, shorten(msg, 200)
	case strings.Contains(lm, "socket exception") || strings.Contains(lm, "socketexception"):
		return "SOCKET_ERROR", types.CatFailure, types.StatusFailure, shorten(msg, 200)
	case strings.Contains(lm, "write concern") || strings.Contains(lm, "writeconcernerror"):
		return "WRITE_CONCERN_ERROR", types.CatFailure, types.StatusFailure, jsonAttrSummary(attr, msg)
	case lc == "network" && (strings.Contains(lm, "error") || strings.Contains(lm, "fail") || strings.Contains(lm, "closed")):
		return "NETWORK_ERROR", types.CatFailure, types.StatusFailure, msg
	case strings.Contains(lm, "authentication failed") || strings.Contains(lm, "auth failed"):
		return "AUTH_FAILURE", types.CatFailure, types.StatusFailure, msg
	case strings.Contains(lm, "assert") || strings.Contains(lm, "fatal"):
		return "FATAL_ERROR", types.CatFailure, types.StatusFailure, msg

	// --- Performance ---
	case strings.Contains(lm, "slow query") || strings.Contains(lm, "command slow"):
		return "SLOW_QUERY", types.CatPerformance, types.StatusWarn, shorten(raw, 200)
	case strings.Contains(lm, "index build") && strings.Contains(lm, "start"):
		return "INDEX_BUILD", types.CatPerformance, types.StatusInfo, "phase=start " + jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "index build") && (strings.Contains(lm, "complete") || strings.Contains(lm, "done")):
		return "INDEX_BUILD", types.CatPerformance, types.StatusSuccess, "phase=complete " + jsonAttrSummary(attr, msg)
	case strings.Contains(lm, "exceeded time limit") || strings.Contains(lm, "maxtimemsexpired"):
		return "OP_TIMEOUT", types.CatPerformance, types.StatusFailure, shorten(msg, 200)
	case strings.Contains(lm, "cursor") && strings.Contains(lm, "timed out"):
		return "CURSOR_TIMEOUT", types.CatPerformance, types.StatusWarn, shorten(msg, 200)
	}

	// Component-based fallback
	switch lc {
	case "repl":
		if strings.Contains(lm, "primary") {
			return "REPL_STATE", types.CatRole, types.StatusInfo, msg
		}
		if isOplogReplicationLine(lm) {
			return "REPL_OPLOG", types.CatReplication, types.StatusInfo, shorten(msg, 160)
		}
		return "REPL", types.CatReplication, types.StatusInfo, shorten(msg, 160)
	case "sharding", "shard":
		return "SHARDING", types.CatSharding, types.StatusInfo, shorten(msg, 160)
	case "write":
		if strings.Contains(lm, "slow") {
			return "SLOW_WRITE", types.CatPerformance, types.StatusWarn, msg
		}
	}
	return "", "", types.StatusUnknown, ""
}

func parseTextLine(path, line string, ctx *ScanContext) *types.StructuredEvent {
	ts, _, ok := regex.SearchDateFromLog(line)
	if !ok {
		return nil
	}
	low := strings.ToLower(line)
	var et string
	var cat types.EventCategory
	var st types.EventStatus
	var details string

	switch {
	case strings.Contains(low, "mongodb starting"):
		et, cat, st, details = "PROCESS_START", types.CatNode, types.StatusSuccess, shorten(line, 200)
	case strings.Contains(low, "waiting for connections"):
		et, cat, st, details = "NODE_LISTEN", types.CatNode, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "replica set config:"):
		et, cat, st, details = "RS_CONFIG", types.CatTopology, types.StatusInfo, shorten(line, 220)
	case reMemberStateLine.MatchString(line):
		m := reMemberStateLine.FindStringSubmatch(line)
		if len(m) > 1 {
			et, cat, st, details = "MEMBER_STATE", types.CatRole, types.StatusInfo, "state="+m[1]
		} else {
			et, cat, st, details = "MEMBER_STATE", types.CatRole, types.StatusInfo, shorten(line, 200)
		}
	case strings.Contains(low, "transition to primary"):
		et, cat, st, details = "PRIMARY_TRANSITION", types.CatRole, types.StatusSuccess, shorten(line, 200)
	case strings.Contains(low, "stepped down") || strings.Contains(low, "stepping down"):
		et, cat, st, details = "STEPDOWN", types.CatRole, types.StatusWarn, shorten(line, 200)
	case !textHasElectionNoise(low) && strings.Contains(low, "election") && strings.Contains(low, "succeed"):
		et, cat, st, details = "ELECTION_SUCCESS", types.CatRole, types.StatusSuccess, shorten(line, 200)
	case !textHasElectionNoise(low) && strings.Contains(low, "election") && (strings.Contains(low, "fail") || strings.Contains(low, "abort")):
		et, cat, st, details = "ELECTION_FAIL", types.CatRole, types.StatusFailure, shorten(line, 200)
	case textMentionsRealElection(low):
		et, cat, st, details = "ELECTION", types.CatRole, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "rollback"):
		et, cat, st, details = "ROLLBACK", types.CatReplication, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "initial sync"):
		et, cat, st, details = "INITIAL_SYNC", types.CatReplication, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "heartbeat") && (strings.Contains(low, "fail") || strings.Contains(low, "timeout")):
		et, cat, st, details = "HEARTBEAT_FAIL", types.CatTopology, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "heartbeat"):
		et, cat, st, details = "HEARTBEAT", types.CatTopology, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "replsetinitiate") || strings.Contains(low, "initiating a replica set"):
		et, cat, st, details = "RS_INITIATE", types.CatTopology, types.StatusSuccess, shorten(line, 200)
	case strings.Contains(low, "reconfig"):
		et, cat, st, details = "RECONFIG", types.CatTopology, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "chunk") && strings.Contains(low, "move"):
		et, cat, st, details = "CHUNK_MIGRATION", types.CatSharding, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "balancer"):
		et, cat, st, details = "BALANCER", types.CatSharding, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "authentication failed"):
		et, cat, st, details = "AUTH_FAILURE", types.CatFailure, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "connection reset") || strings.Contains(low, "network error"):
		et, cat, st, details = "NETWORK_ERROR", types.CatFailure, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "shutting down") || strings.Contains(low, "now exiting"):
		et, cat, st, details = "PROCESS_SHUTDOWN", types.CatFailure, types.StatusWarn, shorten(line, 200)
	case strings.Contains(low, "fatal") || strings.Contains(low, "assertion"):
		et, cat, st, details = "FATAL_ERROR", types.CatFailure, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "slow query"):
		et, cat, st, details = "SLOW_QUERY", types.CatPerformance, types.StatusWarn, shorten(line, 200)
	case strings.Contains(low, "changed sync source") || (strings.Contains(low, "sync source") && !strings.Contains(low, "initial sync")):
		et, cat, st, details = "SYNC_SOURCE_CHANGE", types.CatReplication, types.StatusInfo, shorten(line, 200)
	case strings.Contains(low, "oplog window"):
		et, cat, st, details = "OPLOG_WINDOW", types.CatReplication, types.StatusWarn, shorten(line, 200)
	case strings.Contains(low, "not enough") && strings.Contains(low, "majority"):
		et, cat, st, details = "QUORUM_LOSS", types.CatTopology, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "quorum check") && strings.Contains(low, "succeeded"):
		et, cat, st, details = "QUORUM_OK", types.CatTopology, types.StatusSuccess, shorten(line, 200)
	case strings.Contains(low, "not reachable"):
		et, cat, st, details = "MEMBER_UNREACHABLE", types.CatTopology, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "connection pool"):
		et, cat, st, details = "CONN_POOL_ERROR", types.CatFailure, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "socket exception") || strings.Contains(low, "socketexception"):
		et, cat, st, details = "SOCKET_ERROR", types.CatFailure, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "dns resolution") || strings.Contains(low, "dns lookup"):
		et, cat, st, details = "DNS_ERROR", types.CatFailure, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "write concern") || strings.Contains(low, "writeconcernerror"):
		et, cat, st, details = "WRITE_CONCERN_ERROR", types.CatFailure, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "migration started"):
		et, cat, st, details = "CHUNK_MIGRATION", types.CatSharding, types.StatusInfo, "phase=start "+shorten(line, 180)
	case strings.Contains(low, "migration committed"):
		et, cat, st, details = "CHUNK_MIGRATION", types.CatSharding, types.StatusSuccess, "phase=complete "+shorten(line, 180)
	case strings.Contains(low, "migration aborted"):
		et, cat, st, details = "CHUNK_MIGRATION", types.CatSharding, types.StatusFailure, "phase=abort "+shorten(line, 180)
	case strings.Contains(low, "index build") && strings.Contains(low, "start"):
		et, cat, st, details = "INDEX_BUILD", types.CatPerformance, types.StatusInfo, "phase=start "+shorten(line, 180)
	case strings.Contains(low, "index build") && (strings.Contains(low, "complete") || strings.Contains(low, "done")):
		et, cat, st, details = "INDEX_BUILD", types.CatPerformance, types.StatusSuccess, "phase=complete "+shorten(line, 180)
	case strings.Contains(low, "exceeded time limit") || strings.Contains(low, "maxtimemsexpired"):
		et, cat, st, details = "OP_TIMEOUT", types.CatPerformance, types.StatusFailure, shorten(line, 200)
	case strings.Contains(low, "cursor") && strings.Contains(low, "timed out"):
		et, cat, st, details = "CURSOR_TIMEOUT", types.CatPerformance, types.StatusWarn, shorten(line, 200)
	case isOplogReplicationLine(low) && reSlowMS.MatchString(line):
		et, cat, st, details = "OPLOG_TAIL_SLOW", types.CatReplication, types.StatusWarn, shorten(line, 200)
	case reSlowMS.MatchString(line):
		et, cat, st, details = "LONG_RUNNING_CMD", types.CatPerformance, types.StatusWarn, shorten(line, 200)
	case strings.Contains(low, "secondary") && strings.Contains(low, "transition"):
		et, cat, st, details = "SECONDARY_TRANSITION", types.CatRole, types.StatusInfo, shorten(line, 200)
	default:
		return nil
	}
	return finalizeEvent(path, line, ctx, ts, et, cat, st, details)
}

func finalizeEvent(path, raw string, ctx *ScanContext, ts time.Time, et string, cat types.EventCategory, st types.EventStatus, details string) *types.StructuredEvent {
	if ctx.RSName != "" && !strings.Contains(details, "rs=") {
		details = fmt.Sprintf("rs=%s %s", ctx.RSName, details)
	}
	if ctx.Version != "" && strings.HasPrefix(et, "PROCESS_START") {
		details = fmt.Sprintf("version=%s %s", ctx.Version, details)
	}
	if ctx.Process != "" && !strings.Contains(details, "process=") &&
		(cat == types.CatNode || strings.HasPrefix(et, "PROCESS_") || et == "NODE_LISTEN") {
		details = fmt.Sprintf("process=%s %s", ctx.Process, strings.TrimSpace(details))
	}
	return &types.StructuredEvent{
		Time:       ts,
		Node:       ctx.NodeLabel(),
		HostPort:   ctx.HostPort(),
		EventType:  et,
		Status:     st,
		Details:    strings.TrimSpace(details),
		Category:   cat,
		SourceFile: path,
		Raw:        raw,
	}
}

func jsonAttrSummary(attr map[string]interface{}, msg string) string {
	if attr == nil {
		return msg
	}
	parts := []string{}
	for _, k := range []string{
		"term", "newState", "oldState", "from", "to", "syncSource",
		"member", "name", "error", "code", "replicaSetId",
		"namespace", "shard", "donorShard", "recipientShard",
		"indexName", "buildUUID",
	} {
		if v, ok := attr[k]; ok {
			parts = append(parts, fmt.Sprintf("%s=%v", k, v))
		}
	}
	if len(parts) == 0 {
		return msg
	}
	return strings.Join(parts, " ")
}

func jsonLagSummary(attr map[string]interface{}, msg string) string {
	if attr == nil {
		return msg
	}
	parts := []string{}
	for _, k := range []string{"lag", "replicationLag", "member", "syncSource"} {
		if v, ok := attr[k]; ok {
			parts = append(parts, fmt.Sprintf("%s=%v", k, v))
		}
	}
	if len(parts) == 0 {
		return msg
	}
	return strings.Join(parts, " ")
}

func shorten(s string, n int) string {
	s = strings.ReplaceAll(strings.TrimSpace(s), "\t", " ")
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
