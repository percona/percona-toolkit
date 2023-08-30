package regex

import (
	"regexp"
	"strings"

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
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			nodename := submatches[groupNodeName]
			nodename, _, _ = strings.Cut(nodename, ".")
			ctx.AddOwnName(nodename)
			return ctx, types.SimpleDisplayer("local name:" + nodename)
		},
		Verbosity: types.DebugMySQL,
	},

	"RegexNodeIPFromEnv": &types.LogRegex{
		Regex:         regexp.MustCompile(". NODE_IP="),
		InternalRegex: regexp.MustCompile("NODE_IP=" + regexNodeIP),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			ip := submatches[groupNodeIP]
			ctx.AddOwnIP(ip)
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
		Regex: regexp.MustCompile("^{\"log\":\".*GCache::RingBuffer initial scan"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer("recovering gcache")
		},
	},
}
