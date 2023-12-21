package regex

import (
	"regexp"
	"time"

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
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			logCtx.Desynced = true

			node := submatches[groupNodeName]
			return logCtx, func(logCtx types.LogCtx) string {
				if utils.SliceContains(logCtx.OwnNames, node) {
					return utils.Paint(utils.YellowText, "desyncs itself from group")
				}
				return node + utils.Paint(utils.YellowText, " desyncs itself from group")
			}
		},
	},

	"RegexResync": &types.LogRegex{
		Regex:         regexp.MustCompile("resyncs itself to group"),
		InternalRegex: regexp.MustCompile("\\(" + regexNodeName + "\\) resyncs"),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			logCtx.Desynced = false
			node := submatches[groupNodeName]
			return logCtx, func(logCtx types.LogCtx) string {
				if utils.SliceContains(logCtx.OwnNames, node) {
					return utils.Paint(utils.YellowText, "resyncs itself to group")
				}
				return node + utils.Paint(utils.YellowText, " resyncs itself to group")
			}
		},
	},

	"RegexInconsistencyVoteInit": &types.LogRegex{
		Regex:         regexp.MustCompile("initiates vote on"),
		InternalRegex: regexp.MustCompile("Member " + regexIdx + "\\(" + regexNodeName + "\\) initiates vote on " + regexUUID + ":" + regexSeqno + "," + regexErrorMD5 + ":  (?P<error>.*), Error_code:"),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			node := submatches[groupNodeName]
			seqno := submatches[groupSeqno]
			errormd5 := submatches[groupErrorMD5]
			errorstring := submatches["error"]

			c := types.Conflict{
				InitiatedBy: []string{node},
				Seqno:       seqno,
				VotePerNode: map[string]types.ConflictVote{node: types.ConflictVote{MD5: errormd5, Error: errorstring}},
			}

			logCtx.Conflicts = logCtx.Conflicts.Merge(c)

			return logCtx, func(logCtx types.LogCtx) string {

				if utils.SliceContains(logCtx.OwnNames, node) {
					return utils.Paint(utils.YellowText, "inconsistency vote started") + "(seqno:" + seqno + ")"
				}

				return utils.Paint(utils.YellowText, "inconsistency vote started by "+node) + "(seqno:" + seqno + ")"
			}
		},
	},

	"RegexInconsistencyVoteRespond": &types.LogRegex{
		Regex:         regexp.MustCompile("responds to vote on "),
		InternalRegex: regexp.MustCompile("Member " + regexIdx + "\\(" + regexNodeName + "\\) responds to vote on " + regexUUID + ":" + regexSeqno + "," + regexErrorMD5 + ": (?P<error>.*)"),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			node := submatches[groupNodeName]
			seqno := submatches[groupSeqno]
			errormd5 := submatches[groupErrorMD5]
			errorstring := submatches["error"]

			latestConflict := logCtx.Conflicts.ConflictWithSeqno(seqno)
			if latestConflict == nil {
				return logCtx, nil
			}
			latestConflict.VotePerNode[node] = types.ConflictVote{MD5: errormd5, Error: errorstring}

			return logCtx, func(logCtx types.LogCtx) string {

				for _, name := range logCtx.OwnNames {
					vote, ok := latestConflict.VotePerNode[name]
					if !ok || node != name {
						continue
					}
					return voteResponse(vote, *latestConflict)
				}

				return ""
			}
		},
	},

	// This one does not need to be variabilized
	// percona-xtradb-cluster-galera/galera/src/replicator_smm.cpp:2405
	// case 1:         /* majority disagrees */
	//     msg << "Vote 0 (success) on " << gtid
	//         << " is inconsistent with group. Leaving cluster.";
	//     goto fail;
	"RegexInconsistencyVoteInconsistentWithGroup": &types.LogRegex{
		Regex:         regexp.MustCompile("is inconsistent with group. Leaving cluster"),
		InternalRegex: regexp.MustCompile("Vote [0-9] \\(success\\) on " + regexUUID + ":" + regexSeqno + " is inconsistent with group. Leaving cluster"),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			seqno := submatches[groupSeqno]
			latestConflict := logCtx.Conflicts.ConflictWithSeqno(seqno)
			if latestConflict == nil {
				return logCtx, nil
			}
			if len(logCtx.OwnNames) > 0 {
				latestConflict.VotePerNode[logCtx.OwnNames[len(logCtx.OwnNames)-1]] = types.ConflictVote{Error: "Success", MD5: "0000000000000000"}
			}
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.RedText, "vote (success) inconsistent, leaving cluster"))
		},
	},

	"RegexInconsistencyVoted": &types.LogRegex{
		Regex: regexp.MustCompile("Inconsistency detected: Inconsistent by consensus"),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer(utils.Paint(utils.RedText, "found inconsistent by vote"))
		},
	},

	"RegexInconsistencyWinner": &types.LogRegex{
		Regex:         regexp.MustCompile("Winner: "),
		InternalRegex: regexp.MustCompile("Winner: " + regexErrorMD5),
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			errormd5 := submatches[groupErrorMD5]

			if len(logCtx.Conflicts) == 0 {
				return logCtx, nil // nothing to guess
			}

			c := logCtx.Conflicts.ConflictFromMD5(errormd5)
			if c == nil {
				// some votes have been observed to be logged again
				// sometimes days after the initial one
				// the winner outcomes is not even always the initial one

				// as they don't add any helpful context, we should ignore
				// plus, it would need multiline regexes, which is not supported here
				return logCtx, nil
			}
			c.Winner = errormd5

			return logCtx, func(logCtx types.LogCtx) string {
				out := "consistency vote(seqno:" + c.Seqno + "): "
				for _, name := range logCtx.OwnNames {

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
		Handler: func(submatches map[string]string, logCtx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			if len(logCtx.OwnNames) == 0 {
				return logCtx, nil
			}

			errormd5 := submatches[groupErrorMD5]
			seqno := submatches[groupSeqno]
			c := logCtx.Conflicts.ConflictWithSeqno(seqno)
			if c == nil { // the actual vote could have been lost
				return logCtx, nil
			}
			vote := types.ConflictVote{MD5: errormd5}
			c.VotePerNode[logCtx.OwnNames[len(logCtx.OwnNames)-1]] = vote

			return logCtx, types.SimpleDisplayer(voteResponse(vote, *c))
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
