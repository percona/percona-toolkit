package regex

import (
	"regexp"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func init() {
	setType(types.ApplicativeRegexType, ApplicativeMap)
}

var ApplicativeMap = types.RegexMap{

	"RegexDesync": &types.LogRegex{
		Regex:         regexp.MustCompile("desyncs itself from group"),
		InternalRegex: regexp.MustCompile("\\(" + regexNodeName + "\\) desyncs"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.Desynced = true

			node := submatches[groupNodeName]
			return ctx, func(ctx types.LogCtx) string {
				if utils.SliceContains(ctx.OwnNames, node) {
					return utils.Paint(utils.YellowText, "desyncs itself from group")
				}
				return node + utils.Paint(utils.YellowText, " desyncs itself from group")
			}
		},
	},

	"RegexResync": &types.LogRegex{
		Regex:         regexp.MustCompile("resyncs itself to group"),
		InternalRegex: regexp.MustCompile("\\(" + regexNodeName + "\\) resyncs"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.Desynced = false
			node := submatches[groupNodeName]
			return ctx, func(ctx types.LogCtx) string {
				if utils.SliceContains(ctx.OwnNames, node) {
					return utils.Paint(utils.YellowText, "resyncs itself to group")
				}
				return node + utils.Paint(utils.YellowText, " resyncs itself to group")
			}
		},
	},

	"RegexInconsistencyVoteInit": &types.LogRegex{
		Regex:         regexp.MustCompile("initiates vote on"),
		InternalRegex: regexp.MustCompile("Member " + regexIdx + "\\(" + regexNodeName + "\\) initiates vote on " + regexUUID + ":" + regexSeqno + "," + regexErrorMD5 + ":  (?P<error>.*), Error_code:"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			node := submatches[groupNodeName]
			seqno := submatches[groupSeqno]
			errormd5 := submatches[groupErrorMD5]
			errorstring := submatches["error"]

			c := types.Conflict{
				InitiatedBy: []string{node},
				Seqno:       seqno,
				VotePerNode: map[string]types.ConflictVote{node: types.ConflictVote{MD5: errormd5, Error: errorstring}},
			}

			ctx.Conflicts = ctx.Conflicts.Merge(c)

			return ctx, func(ctx types.LogCtx) string {

				if utils.SliceContains(ctx.OwnNames, node) {
					return utils.Paint(utils.YellowText, "inconsistency vote started") + "(seqno:" + seqno + ")"
				}

				return utils.Paint(utils.YellowText, "inconsistency vote started by "+node) + "(seqno:" + seqno + ")"
			}
		},
	},

	"RegexInconsistencyVoteRespond": &types.LogRegex{
		Regex:         regexp.MustCompile("responds to vote on "),
		InternalRegex: regexp.MustCompile("Member " + regexIdx + "\\(" + regexNodeName + "\\) responds to vote on " + regexUUID + ":" + regexSeqno + "," + regexErrorMD5 + ": (?P<error>.*)"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			node := submatches[groupNodeName]
			seqno := submatches[groupSeqno]
			errormd5 := submatches[groupErrorMD5]
			errorstring := submatches["error"]

			latestConflict := ctx.Conflicts.ConflictWithSeqno(seqno)
			if latestConflict == nil {
				return ctx, nil
			}
			latestConflict.VotePerNode[node] = types.ConflictVote{MD5: errormd5, Error: errorstring}

			return ctx, func(ctx types.LogCtx) string {

				for _, name := range ctx.OwnNames {
					vote, ok := latestConflict.VotePerNode[name]
					if !ok {
						continue
					}

					return voteResponse(vote, *latestConflict)
				}

				return ""
			}
		},
	},

	"RegexInconsistencyVoted": &types.LogRegex{
		Regex: regexp.MustCompile("Inconsistency detected: Inconsistent by consensus"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "found inconsistent by vote"))
		},
	},

	"RegexInconsistencyWinner": &types.LogRegex{
		Regex:         regexp.MustCompile("Winner: "),
		InternalRegex: regexp.MustCompile("Winner: " + regexErrorMD5),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			errormd5 := submatches[groupErrorMD5]

			if len(ctx.Conflicts) == 0 {
				return ctx, nil // nothing to guess
			}

			c := ctx.Conflicts.ConflictFromMD5(errormd5)
			if c == nil {
				// some votes have been observed to be logged again
				// sometimes days after the initial one
				// the winner outcomes is not even always the initial one

				// as they don't add any helpful context, we should ignore
				// plus, it would need multiline regexes, which is not supported here
				return ctx, nil
			}
			c.Winner = errormd5

			return ctx, func(ctx types.LogCtx) string {
				out := "consistency vote(seqno:" + c.Seqno + "): "
				for _, name := range ctx.OwnNames {

					vote, ok := c.VotePerNode[name]
					if !ok {
						continue
					}

					if vote.MD5 == c.Winner {
						return out + utils.Paint(utils.GreenText, "won")
					}
					return out + utils.Paint(utils.RedText, "lost")
				}
				return ""
			}
		},
	},

	"RegexInconsistencyRecovery": &types.LogRegex{
		Regex:         regexp.MustCompile("Recovering vote result from history"),
		InternalRegex: regexp.MustCompile("Recovering vote result from history: " + regexUUID + ":" + regexSeqno + "," + regexErrorMD5),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			if len(ctx.OwnNames) == 0 {
				return ctx, nil
			}

			errormd5 := submatches[groupErrorMD5]
			seqno := submatches[groupSeqno]
			c := ctx.Conflicts.ConflictWithSeqno(seqno)
			if c == nil { // the actual vote could have been lost
				return ctx, nil
			}
			vote := types.ConflictVote{MD5: errormd5}
			c.VotePerNode[ctx.OwnNames[len(ctx.OwnNames)-1]] = vote

			return ctx, types.SimpleDisplayer(voteResponse(vote, *c))
		},
		Verbosity: types.DebugMySQL,
	},
}

func voteResponse(vote types.ConflictVote, conflict types.Conflict) string {
	out := "consistency vote(seqno:" + conflict.Seqno + "): voted "

	initError := conflict.VotePerNode[conflict.InitiatedBy[0]]
	switch vote.MD5 {
	case "0000000000000000":
		out += "Success"
	case initError.MD5:
		out += "same error"
	default:
		out += "different error"
	}

	return out

}
