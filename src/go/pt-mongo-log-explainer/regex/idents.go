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

package regex

import (
	"regexp"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
)

func init() {
	setType(types.IdentRegexType, IdentsMap)
}

var IdentsMap = types.RegexMap{
	// RegexMongoVersion captures the SERVER version only from authoritative
	// contexts: the legacy "db version vX.Y.Z" startup line and the structured
	// (JSON) Build Info field "buildInfo":{"version":"X.Y.Z"}. It deliberately
	// anchors to those prefixes so it cannot mis-capture unrelated number triples
	// such as the 127.0.0.1 loopback IP, an OS release (e.g. 2023.9.20250929),
	// or a client driver version ("driver":{"version":"1.17.4"}).
	"RegexMongoVersion": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)db version v[0-9]|"buildInfo"\s*:\s*\{\s*"version"`),
		InternalRegex: regexp.MustCompile(`(?i)(?:db version v|"buildInfo"\s*:\s*\{\s*"version"\s*:\s*"v?)(?P<ver>[0-9]+\.[0-9]+\.[0-9]+[-.0-9A-Za-z]*)`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			v := submatches["ver"]
			if v != "" {
				logCtx.Version = v
			}
			return logCtx, types.SimpleDisplayer("version " + v)
		},
		Verbosity: types.DebugContext,
	},

	"RegexWaitingForConnections": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)waiting for connections`),
		InternalRegex: regexp.MustCompile(`(?i)(port|\"port\")\D*(?P<port>[0-9]{2,6})`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			p := submatches["port"]
			if p == "" {
				return logCtx, nil
			}
			name := "listen:" + p
			logCtx.AddOwnName(name, date)
			return logCtx, types.SimpleDisplayer("listening port " + p)
		},
		Verbosity: types.DebugContext,
	},

	"RegexBindIP": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)bindIp.*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+`),
		InternalRegex: regexp.MustCompile(`bindIp[^0-9]*(?P<` + groupHost + `>[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			ip := submatches[groupHost]
			if ip == "" || ip == "0.0.0.0" || ip == "127.0.0.1" {
				return logCtx, nil
			}
			logCtx.AddOwnIP(ip, date)
			return logCtx, types.SimpleDisplayer("bind " + ip)
		},
		Verbosity: types.DebugContext,
	},

	// RegexConnectionAccepted captures peer IPs from both the legacy text form
	// ("connection accepted from IP:PORT") and the structured (JSON) form
	// ("msg":"Connection accepted","attr":{"remote":"IP:PORT"}). Loopback peers
	// carry no cluster-identity value and are skipped.
	"RegexConnectionAccepted": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)connection accepted`),
		InternalRegex: regexp.MustCompile(`(?i)(?:from |"remote"\s*:\s*")(?P<` + groupHost + `>[0-9.]+):(?P<` + groupPort + `>[0-9]+)`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			ip := submatches[groupHost]
			if ip == "" || ip == "127.0.0.1" {
				return logCtx, nil
			}
			translate.AddPeerIP(ip, date)
			return logCtx, types.SimpleDisplayer("peer " + ip)
		},
		Verbosity: types.DebugContext,
	},

	"RegexConfigHost": &types.LogRegex{
		Regex:         regexp.MustCompile(`\"host\"\s*:\s*\"`),
		InternalRegex: regexp.MustCompile(`\"host\"\s*:\s*\"(?P<h>[a-zA-Z0-9._-]+):(?P<p>[0-9]{2,6})\"`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			h := utils.ShortNodeName(submatches["h"])
			hostport := h + ":" + submatches["p"]
			translate.AddHashToNodeName(hostport, h, date)
			if ipv4RE.MatchString(h) {
				logCtx.AddOwnIP(h, date)
			} else {
				logCtx.AddOwnName(h, date)
			}
			return logCtx, types.SimpleDisplayer("cfg member " + hostport)
		},
		Verbosity: types.DebugContext,
	},

	"RegexReplSetName": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)replSet|replica set`),
		InternalRegex: regexp.MustCompile(`(?i)(replSet|replica set|replicaSet)[^a-zA-Z0-9_]+(?P<rs>[a-zA-Z0-9_-]{2,64})`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			rs := submatches["rs"]
			rsLower := strings.ToLower(rs)
			if rs == "" || rsLower == "initiate" || rsLower == "config" ||
				rsLower == "member" || rsLower == "starting" || rsLower == "state" {
				return logCtx, nil
			}
			logCtx.AddOwnName("rs:"+rs, date)
			return logCtx, types.SimpleDisplayer("replSet " + rs)
		},
		Verbosity: types.DebugContext,
	},

	"RegexMemberIDHost": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)member.*_id.*host`),
		InternalRegex: regexp.MustCompile(`(?i)_id:\s*(?P<mid>[0-9]+).*host:\s*\"(?P<h>[a-zA-Z0-9._-]+):(?P<p>[0-9]{2,6})\"`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			h := utils.ShortNodeName(submatches["h"])
			mid := submatches["mid"]
			if mid != "" {
				translate.AddHashToNodeName(mid, h, date)
			}
			return logCtx, types.SimpleDisplayer("member " + mid + " " + h)
		},
		Verbosity: types.DebugContext,
	},

	"RegexElectionObjectId": &types.LogRegex{
		Regex:         regexp.MustCompile(`ObjectId\('\s*[a-fA-F0-9]{24}\s*'\)`),
		InternalRegex: regexp.MustCompile(`ObjectId\('\s*(?P<oid>[a-fA-F0-9]{24})\s*'\)`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			oid := strings.ToLower(submatches["oid"])
			logCtx.AddOwnHash(oid, date)
			return logCtx, types.SimpleDisplayer("id " + oid[:8])
		},
		Verbosity: types.DebugContext,
	},
}
