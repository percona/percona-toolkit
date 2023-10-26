package regex

import (
	"regexp"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
)

func init() {
	setType(types.PXCOperatorRegexType, PXCOperatorMap)
}

// Regexes from this type should only be about operator extra logs
// it should not contain Galera logs
// Specifically operators are dumping configuration files, recoveries, script outputs, ...
// only those should be handled here, they are specific to pxc operator but still very insightful
var PXCOperatorMap = types.RegexMap{
	"RegexNodeNameFromEnv": &types.LogRegex{
		Regex:         regexp.MustCompile(". NODE_NAME="),
		InternalRegex: regexp.MustCompile("NODE_NAME=" + regexNodeName),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			nodename := submatches[groupNodeName]
			nodename, _, _ = strings.Cut(nodename, ".")
			ctx.AddOwnName(nodename, date)
			return ctx, types.SimpleDisplayer("local name:" + nodename)
		},
		Verbosity: types.DebugMySQL,
	},

	"RegexNodeIPFromEnv": &types.LogRegex{
		Regex:         regexp.MustCompile(". NODE_IP="),
		InternalRegex: regexp.MustCompile("NODE_IP=" + regexNodeIP),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			ip := submatches[groupNodeIP]
			ctx.AddOwnIP(ip, date)
			return ctx, types.SimpleDisplayer("local ip:" + ip)
		},
		Verbosity: types.DebugMySQL,
	},

	// Why is it not in regular "views" regexes:
	// it could have been useful as an "verbosity=types.Detailed" regexes, very rarely
	// but in context of operators, it is actually a very important information
	"RegexGcacheScan": &types.LogRegex{
		// those "operators" regexes do not have the log prefix added implicitely. It's not strictly needed, but
		// it will help to avoid catching random piece of log out of order
		Regex: regexp.MustCompile(k8sprefix + ".*GCache::RingBuffer initial scan"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer("recovering gcache")
		},
	},

	// Unusual regex: because operators log does not handle newlines, it is contracted in a single line
	// which the common "IdentsMap" regexes will miss. Even if they would catch it, it would only catch a single one, not all info
	// so this regex is about capturing subgroups to re-handle each them to the appropriate existing IdentsMap regex
	"RegexOperatorMemberAssociations": &types.LogRegex{
		Regex:         regexp.MustCompile("================================================.*View:"),
		InternalRegex: regexp.MustCompile("own_index: " + regexIdx + ".*(?P<memberlog>" + IdentsMap["RegexMemberCount"].Regex.String() + ")(?P<compiledAssocations>(....-?[0-9]{1,2}(\\.-?[0-9])?: [a-z0-9]+-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]+, [a-zA-Z0-9-_\\.]+)+)"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			ctx.MyIdx = submatches[groupIdx]

			var (
				displayer types.LogDisplayer
				msg       string
			)

			ctx, displayer = IdentsMap["RegexMemberCount"].Handle(ctx, submatches["memberlog"], date)
			msg += displayer(ctx) + "; "

			subAssociations := strings.Split(submatches["compiledAssocations"], "\\n\\t")
			if len(subAssociations) < 2 {
				return ctx, types.SimpleDisplayer(msg)
			}
			for _, subAssocation := range subAssociations[1:] {
				// better to reuse the idents regex
				ctx, displayer = IdentsMap["RegexMemberAssociations"].Handle(ctx, subAssocation, date)
				msg += displayer(ctx) + "; "
			}
			return ctx, types.SimpleDisplayer(msg)
		},
		Verbosity: types.DebugMySQL,
	},
}
