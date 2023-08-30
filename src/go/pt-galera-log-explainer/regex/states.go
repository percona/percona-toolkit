package regex

import (
	"regexp"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func init() {
	setType(types.StatesRegexType, StatesMap)
}

var (
	shiftFunc = func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

		ctx.SetState(submatches["state2"])
		log = utils.PaintForState(submatches["state1"], submatches["state1"]) + " -> " + utils.PaintForState(submatches["state2"], submatches["state2"])

		return ctx, types.SimpleDisplayer(log)
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
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			var displayer types.LogDisplayer
			ctx, displayer = shiftFunc(submatches, ctx, log)

			return ctx, types.SimpleDisplayer("(restored)" + displayer(ctx))
		},
	},
}

//  [Note] [MY-000000] [WSREP] Server status change connected -> joiner
