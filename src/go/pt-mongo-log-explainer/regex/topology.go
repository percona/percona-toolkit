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
	"strconv"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
)

func init() {
	setType(types.TopologyRegexType, TopologyMap)
}

// TopologyMap holds replica-set topology / configuration events.
var TopologyMap = types.RegexMap{
	"RegexReplSetInitiate": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)replSetInitiate|initiating a replica set`),
		InternalRegex: regexp.MustCompile(`(?i)replSetInitiate|initiating a replica set`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			logCtx.MemberCount = 1
			return logCtx, types.SimpleDisplayer("replSet initiate")
		},
		Verbosity: types.Info,
	},

	"RegexReplicaSetReconfig": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)new replica set config|replSetReconfig|reconfiguring replica set`),
		InternalRegex: regexp.MustCompile(`(?i)new replica set config|replSetReconfig|reconfiguring replica set`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer("replica set reconfig")
		},
		Verbosity: types.Info,
	},

	"RegexMemberCountInConfig": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)members\.[0-9]|"members"\s*:\s*\[`),
		InternalRegex: regexp.MustCompile(`(?i)version:\s*(?P<v>[0-9]+).*members:\s*(?P<n>[0-9]+)`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			if n := submatches["n"]; n != "" {
				if c, err := strconv.Atoi(n); err == nil {
					logCtx.MemberCount = c
					return logCtx, types.SimpleDisplayer("member count " + n)
				}
			}
			return logCtx, types.SimpleDisplayer("topology change")
		},
		Verbosity: types.DebugContext,
	},

	"RegexAddedRemovedMember": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)added .*member|removed .*member|Adding .* to replica set`),
		InternalRegex: regexp.MustCompile(`(?i)(?P<ev>added|removed|Adding)`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer("member " + submatches["ev"])
		},
		Verbosity: types.Info,
	},
}
