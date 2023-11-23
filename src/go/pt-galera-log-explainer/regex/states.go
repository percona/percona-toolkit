package regex

import (
	"regexp"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func init() {
	setType(types.StatesRegexType, StatesMap)
}

var (
	shiftFunc = func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

		newState := submatches["state2"]
		logCtx.SetState(newState)

		if newState == "DONOR" || newState == "JOINER" {
			logCtx.ConfirmSSTMetadata(date)
		}

		log = utils.PaintForState(submatches["state1"], submatches["state1"]) + " -> " + utils.PaintForState(submatches["state2"], submatches["state2"])

		return logCtx, types.SimpleDisplayer(log)
	}
	shiftRegex = regexp.MustCompile("(?P<state1>[A-Z]+) -> (?P<state2>[A-Z]+)")
)

var StatesMap = types.RegexMap{
	"RegexShift": &types.LogRegex{
		Regex:         regexp.MustCompile("Shifting"),
		InternalRegex: shiftRegex,
		Handler:       shiftFunc,
	},

	"RegexRestoredState": &types.LogRegex{
		Regex:         regexp.MustCompile("Restored state"),
		InternalRegex: shiftRegex,
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			var displayer types.LogDisplayer
			logCtx, displayer = shiftFunc(submatches, logCtx, log, date)

			return logCtx, types.SimpleDisplayer("(restored)" + displayer(logCtx))
		},
	},
}

//  [Note] [MY-000000] [WSREP] Server status change connected -> joiner
