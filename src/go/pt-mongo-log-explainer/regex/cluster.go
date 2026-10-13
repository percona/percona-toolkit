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
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
)

func init() {
	setType(types.ClusterRegexType, ClusterMap)
}

// ClusterMap holds cluster-level operational events: elections, stepdowns, rollbacks, write concern.
var ClusterMap = types.RegexMap{
	"RegexNotPrimary": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)NotPrimary|not master|not writable primary`),
		InternalRegex: regexp.MustCompile(`(?i)(NotPrimary|not master|not writable primary)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "not primary"))
		},
		Verbosity: types.Info,
	},

	"RegexWriteConcernTimeout": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)wtimeout|write concern`),
		InternalRegex: regexp.MustCompile(`(?i)(wtimeout|WriteConcernFailed|write concern)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "write concern"))
		},
		Verbosity: types.Info,
	},

	"RegexStepDown": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)stepped down|Stepping down|transition to secondary`),
		InternalRegex: regexp.MustCompile(`(?i)(stepped down|Stepping down)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "step down"))
		},
		Verbosity: types.Info,
	},

	"RegexElection": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)election|voteRequest|election succeeded|election failed`),
		InternalRegex: regexp.MustCompile(`(?i)(election|voteRequest)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer("election activity")
		},
		Verbosity: types.Info,
	},

	"RegexRollbackEvent": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)rollback|Rolling back`),
		InternalRegex: regexp.MustCompile(`(?i)(rollback|Rolling back)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			logCtx.SetState("ROLLBACK")
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.RedText, "rollback"))
		},
		Verbosity: types.Info,
	},
}
