package regex

import (
	"regexp"
	"strings"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func init() {
	setType(types.EventsRegexType, EventsMap)
}

var EventsMap = types.RegexMap{
	"RegexStarting": &types.LogRegex{
		Regex:         regexp.MustCompile("starting as process"),
		InternalRegex: regexp.MustCompile("\\(mysqld " + regexVersion + ".*\\)"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.Version = submatches[groupVersion]

			msg := "starting(" + ctx.Version
			if isShutdownReasonMissing(ctx) {
				msg += ", " + utils.Paint(utils.YellowText, "could not catch how/when it stopped")
			}
			msg += ")"
			ctx.SetState("OPEN")

			return ctx, types.SimpleDisplayer(msg)
		},
	},
	"RegexShutdownComplete": &types.LogRegex{
		Regex: regexp.MustCompile("mysqld: Shutdown complete"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "shutdown complete"))
		},
	},
	"RegexTerminated": &types.LogRegex{
		Regex: regexp.MustCompile("mysqld: Terminated"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "terminated"))
		},
	},
	"RegexGotSignal6": &types.LogRegex{
		Regex: regexp.MustCompile("mysqld got signal 6"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "crash: got signal 6"))
		},
	},
	"RegexGotSignal11": &types.LogRegex{
		Regex: regexp.MustCompile("mysqld got signal 11"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "crash: got signal 11"))
		},
	},
	"RegexShutdownSignal": &types.LogRegex{
		Regex: regexp.MustCompile("Normal|Received shutdown"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "received shutdown"))
		},
	},

	// 2023-06-12T07:51:38.135646Z 0 [Warning] [MY-000000] [Galera] Exception while mapping writeset addr: 0x7fb668d4e568, seqno: 2770385572449823232, size: 73316, ctx: 0x56128412e0c0, flags: 1. store: 1, type: 32 into [555, 998): 'deque::_M_new_elements_at_back'. Aborting GCache recovery.

	"RegexAborting": &types.LogRegex{
		Regex: regexp.MustCompile("Aborting"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "ABORTING"))
		},
	},

	"RegexWsrepLoad": &types.LogRegex{
		Regex: regexp.MustCompile("wsrep_load\\(\\): loading provider library"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("OPEN")
			if regexWsrepLoadNone.MatchString(log) {
				return ctx, types.SimpleDisplayer(utils.Paint(utils.GreenText, "started(standalone)"))
			}
			return ctx, types.SimpleDisplayer(utils.Paint(utils.GreenText, "started(cluster)"))
		},
	},
	"RegexWsrepRecovery": &types.LogRegex{
		//  INFO: WSREP: Recovered position 00000000-0000-0000-0000-000000000000:-1
		Regex: regexp.MustCompile("Recovered position"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			msg := "wsrep recovery"
			// if state is joiner, it can be due to sst
			// if state is open, it is just a start sequence depending on platform
			if isShutdownReasonMissing(ctx) && ctx.State() != "JOINER" && ctx.State() != "OPEN" {
				msg += "(" + utils.Paint(utils.YellowText, "could not catch how/when it stopped") + ")"
			}
			ctx.SetState("RECOVERY")

			return ctx, types.SimpleDisplayer(msg)
		},
	},

	"RegexUnknownConf": &types.LogRegex{
		Regex: regexp.MustCompile("unknown variable"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			split := strings.Split(log, "'")
			v := "?"
			if len(split) > 0 {
				v = split[1]
			}
			if len(v) > 20 {
				v = v[:20] + "..."
			}
			return ctx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "unknown variable") + ": " + v)
		},
	},

	"RegexAssertionFailure": &types.LogRegex{
		Regex: regexp.MustCompile("Assertion failure"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "ASSERTION FAILURE"))
		},
	},
	"RegexBindAddressAlreadyUsed": &types.LogRegex{
		Regex: regexp.MustCompile("asio error .bind: Address already in use"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "bind address already used"))
		},
	},
	"RegexTooManyConnections": &types.LogRegex{
		Regex: regexp.MustCompile("Too many connections"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "too many connections"))
		},
	},

	"RegexReversingHistory": &types.LogRegex{
		Regex:         regexp.MustCompile("Reversing history"),
		InternalRegex: regexp.MustCompile("Reversing history: " + regexSeqno + " -> [0-9]*, this member has applied (?P<diff>[0-9]*) more events than the primary component"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			return ctx, types.SimpleDisplayer(utils.Paint(utils.BrightRedText, "having "+submatches["diff"]+" more events than the other nodes, data loss possible"))
		},
	},
}
var regexWsrepLoadNone = regexp.MustCompile("none")

// isShutdownReasonMissing is returning true if the latest wsrep state indicated a "working" node
func isShutdownReasonMissing(ctx types.LogCtx) bool {
	return ctx.State() != "DESTROYED" && ctx.State() != "CLOSED" && ctx.State() != "RECOVERY" && ctx.State() != ""
}

/*


2023-05-09T17:39:19.955040Z 51 [Warning] [MY-000000] [Galera] failed to replay trx: source: fb9d6310-ee8b-11ed-8aee-f7542ad73e53 version: 5 local: 1 flags: 1 conn_id: 48 trx_id: 2696 tstamp: 1683653959142522853; state: EXECUTING:0->REPLICATING:782->CERTIFYING:3509->APPLYING:3748->COMMITTING:1343->COMMITTED:-1
2023-05-09T17:39:19.955085Z 51 [Warning] [MY-000000] [Galera] Invalid state in replay for trx source: fb9d6310-ee8b-11ed-8aee-f7542ad73e53 version: 5 local: 1 flags: 1 conn_id: 48 trx_id: 2696 tstamp: 1683653959142522853; state: EXECUTING:0->REPLICATING:782->CERTIFYING:3509->APPLYING:3748->COMMITTING:1343->COMMITTED:-1 (FATAL)
         at galera/src/replicator_smm.cpp:replay_trx():1247


2001-01-01T01:01:01.000000Z 0 [ERROR] [MY-000000] [Galera] gcs/src/gcs_group.cpp:group_post_state_exchange():431: Reversing history: 312312 -> 20121, this member has applied 12345 more events than the primary component.Data loss is possible. Must abort.

2023-06-07T02:50:17.288285-06:00 0 [ERROR] WSREP: Requested size 114209078 for '/var/lib/mysql//galera.cache' exceeds available storage space 1: 28 (No space left on device)

2023-01-01 11:33:15 2101097 [ERROR] mariadbd: Disk full (/tmp/#sql-temptable-.....MAI); waiting for someone to free some space... (errno: 28 "No space left on device")

2023-06-13  1:15:27 35 [Note] WSREP: MDL BF-BF conflict

*/
