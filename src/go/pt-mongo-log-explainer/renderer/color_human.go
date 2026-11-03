// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.

package renderer

import (
	"strings"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
)

// eventTypeColor picks a semantic color for the event type column.
func eventTypeColor(et string) utils.Color {
	switch et {
	case "PROCESS_SHUTDOWN", "STEPDOWN", "ELECTION_FAIL", "FATAL_ERROR", "ROLLBACK",
		"AUTH_FAILURE", "NETWORK_ERROR", "HEARTBEAT_FAIL", "QUORUM_LOSS", "MEMBER_UNREACHABLE",
		"CONN_POOL_ERROR", "CONN_POOL_EXHAUSTED", "DNS_ERROR", "SOCKET_ERROR", "WRITE_CONCERN_ERROR",
		"WT_PANIC", "WT_DATA_CORRUPTION":
		return utils.BrightRedText
	case "PROCESS_START", "NODE_LISTEN", "ELECTION_SUCCESS", "PRIMARY_TRANSITION", "QUORUM_OK":
		return utils.BrightGreenText
	case "SECONDARY_TRANSITION", "MEMBER_STATE", "RS_INITIATE", "INITIAL_SYNC":
		return utils.GreenText
	case "ELECTION", "RECONFIG", "RS_CONFIG", "HEARTBEAT", "SYNC_SOURCE_CHANGE", "MEMBER_JOIN", "MEMBER_LEAVE":
		return utils.CyanText
	case "SLOW_QUERY", "SLOW_WRITE", "LONG_RUNNING_CMD", "INDEX_BUILD", "OP_TIMEOUT", "CURSOR_TIMEOUT",
		"OPLOG_TAIL_SLOW", "WT_CACHE_PRESSURE", "WT_CHECKPOINT_SLOW", "FLOW_CONTROL":
		return utils.YellowText
	case "CHUNK_MIGRATION", "BALANCER", "SHARDING":
		return utils.BrightMagentaText
	default:
		if strings.Contains(strings.ToLower(et), "fail") || strings.Contains(strings.ToLower(et), "error") {
			return utils.BrightRedText
		}
		return utils.WhiteText
	}
}

func statusColor(st types.EventStatus) utils.Color {
	switch st {
	case types.StatusFailure:
		return utils.BrightRedText
	case types.StatusSuccess:
		return utils.BrightGreenText
	case types.StatusWarn:
		return utils.YellowText
	case types.StatusInfo:
		return utils.CyanText
	default:
		return utils.WhiteText
	}
}

func formatHumanLine(e *types.StructuredEvent, ts, hp, node string, highlight bool) string {
	if utils.SkipColor {
		return formatHumanPlain(e, ts, hp, node, highlight)
	}

	prefix := ""
	if e.Anomaly != "" && highlight {
		prefix = utils.Paint(utils.BrightYellowText, "[ANOMALY:"+e.Anomaly+"] ")
	}

	et := e.EventType
	st := string(e.Status)

	nc := utils.NodeHue(node)
	ec := eventTypeColor(et)
	sc := statusColor(e.Status)

	// Prefer strong red/green from status when it disagrees with a neutral event color
	if e.Status == types.StatusFailure {
		ec = utils.BrightRedText
	}
	if e.Status == types.StatusSuccess && (et == "MEMBER_STATE" || et == "HEARTBEAT" || et == "REPL") {
		ec = utils.GreenText
	}

	line := prefix +
		utils.Paint(utils.WhiteText, "["+ts+"]") + " " +
		utils.Paint(nc, "["+node+"]") + " " +
		utils.Paint(utils.BrightBlueText, "["+hp+"]") + " " +
		utils.Paint(ec, "["+et+"]") + " " +
		utils.Paint(sc, "["+st+"]") + " " +
		utils.Paint(utils.WhiteText, "["+e.Details+"]")

	return line
}

func formatHumanPlain(e *types.StructuredEvent, ts, hp, node string, highlight bool) string {
	prefix := ""
	if e.Anomaly != "" && highlight {
		prefix = "[ANOMALY:" + e.Anomaly + "] "
	}
	return prefix + "[" + ts + "] [" + node + "] [" + hp + "] [" + e.EventType + "] [" + string(e.Status) + "] [" + e.Details + "]"
}
