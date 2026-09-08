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

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/utils"
)

func init() {
	setType(types.StatesRegexType, StatesMap)
}

var StatesMap = types.RegexMap{
	"RegexTransitionPrimary": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)transition to primary`),
		InternalRegex: regexp.MustCompile(`(?i)transition to primary`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			logCtx.SetState("PRIMARY")
			return logCtx, types.SimpleDisplayer(utils.PaintForState("PRIMARY", "PRIMARY"))
		},
		Verbosity: types.Info,
	},

	"RegexMemberState": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)(member is now in state|transition to member state|entering .* state)`),
		InternalRegex: regexp.MustCompile(`(?i)(?P<st>PRIMARY|SECONDARY|ARBITER|STARTUP2?|RECOVERING|ROLLBACK|REMOVED|DOWN)`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			st := strings.ToUpper(submatches["st"])
			if st == "" {
				return logCtx, nil
			}
			logCtx.SetState(st)
			return logCtx, types.SimpleDisplayer(utils.PaintForState(st, st))
		},
		Verbosity: types.Info,
	},

	"RegexJSONNewState": &types.LogRegex{
		Regex:         regexp.MustCompile(`"newState"`),
		InternalRegex: regexp.MustCompile(`"newState"\s*:\s*"(?P<st>PRIMARY|SECONDARY|ARBITER|STARTUP2?|RECOVERING|ROLLBACK|REMOVED|DOWN)"`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			st := strings.ToUpper(submatches["st"])
			logCtx.SetState(st)
			return logCtx, types.SimpleDisplayer(utils.PaintForState(st, st))
		},
		Verbosity: types.Info,
	},
}
