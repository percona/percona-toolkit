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
	setType(types.EventsRegexType, EventsMap)
}

var EventsMap = types.RegexMap{
	"RegexMongoDBStarting": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)MongoDB starting|mongod.*starting`),
		InternalRegex: regexp.MustCompile(`(?i)MongoDB starting|starting.*mongod`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.GreenText, "mongod starting"))
		},
		Verbosity: types.Info,
	},

	"RegexShutdown": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)Shutting down|now exiting|shutdown: `),
		InternalRegex: regexp.MustCompile(`(?i)(Shutting down|now exiting|shutdown:)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "shutdown"))
		},
		Verbosity: types.Info,
	},

	"RegexFatalAssertion": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)Fatal|assertion.*failed|segmentation fault`),
		InternalRegex: regexp.MustCompile(`(?i)(Fatal assertion|assertion.*failed|segmentation fault)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.RedText, "fatal/assert"))
		},
		Verbosity: types.Info,
	},

	"RegexDBException": &types.LogRegex{
		Regex:         regexp.MustCompile(`DBException|Location[0-9]+`),
		InternalRegex: regexp.MustCompile(`(?P<err>(DBException|Location[0-9]+))`),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.RedText, submatches["err"]))
		},
		Verbosity: types.Info,
	},
}
