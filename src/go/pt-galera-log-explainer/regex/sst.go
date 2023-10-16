package regex

import (
	"regexp"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func init() {
	setType(types.SSTRegexType, SSTMap)
}

var SSTMap = types.RegexMap{
	// TODO: requested state from unknown node
	"RegexSSTRequestSuccess": &types.LogRegex{
		Regex:         regexp.MustCompile("requested state transfer.*Selected"),
		InternalRegex: regexp.MustCompile("Member " + regexIdx + " \\(" + regexNodeName + "\\) requested state transfer.*Selected " + regexIdx + " \\(" + regexNodeName2 + "\\)\\("),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			joiner := utils.ShortNodeName(submatches[groupNodeName])
			donor := utils.ShortNodeName(submatches[groupNodeName2])

			sst := types.SST{
				Donor:  donor,
				Joiner: joiner,
			}

			// here this is a limitation of the handler signature
			// this is the only case when resorting to timestamps is necessary
			selectionTimestamp, _, ok := SearchDateFromLog(log)
			if ok {
				sst.SelectionTimestamp = &selectionTimestamp
			}

			ctx.SSTs[donor] = sst

			return ctx, func(ctx types.LogCtx) string {
				if utils.SliceContains(ctx.OwnNames, joiner) {
					return donor + utils.Paint(utils.GreenText, " will resync local node")
				}
				if utils.SliceContains(ctx.OwnNames, donor) {
					return utils.Paint(utils.GreenText, "local node will resync ") + joiner
				}

				return donor + utils.Paint(utils.GreenText, " will resync ") + joiner
			}
		},
	},

	"RegexSSTResourceUnavailable": &types.LogRegex{
		Regex:         regexp.MustCompile("requested state transfer.*Resource temporarily unavailable"),
		InternalRegex: regexp.MustCompile("Member .* \\(" + regexNodeName + "\\) requested state transfer"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			joiner := submatches[groupNodeName]
			if utils.SliceContains(ctx.OwnNames, joiner) {

				return ctx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "cannot find donor"))
			}

			return ctx, types.SimpleDisplayer(joiner + utils.Paint(utils.YellowText, " cannot find donor"))
		},
	},

	// 2022-12-24T03:28:22.444125Z 0 [Note] WSREP: 0.0 (name): State transfer to 2.0 (name2) complete.
	"RegexSSTComplete": &types.LogRegex{
		Regex:         regexp.MustCompile("State transfer to.*complete"),
		InternalRegex: regexp.MustCompile(regexIdx + " \\(" + regexNodeName + "\\): State transfer to " + regexIdx + " \\(" + regexNodeName2 + "\\) complete"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			donor := utils.ShortNodeName(submatches[groupNodeName])
			joiner := utils.ShortNodeName(submatches[groupNodeName2])
			displayType := "SST"
			if ctx.SSTs[donor].Type != "" {
				displayType = ctx.SSTs[donor].Type
			}
			delete(ctx.SSTs, donor)

			return ctx, func(ctx types.LogCtx) string {
				if utils.SliceContains(ctx.OwnNames, joiner) {
					return utils.Paint(utils.GreenText, "got "+displayType+" from ") + donor
				}
				if utils.SliceContains(ctx.OwnNames, donor) {
					return utils.Paint(utils.GreenText, "finished sending "+displayType+" to ") + joiner
				}

				return donor + utils.Paint(utils.GreenText, " synced ") + joiner
			}
		},
	},

	// some weird ones:
	// 2022-12-24T03:27:41.966118Z 0 [Note] WSREP: 0.0 (name): State transfer to -1.-1 (left the group) complete.
	"RegexSSTCompleteUnknown": &types.LogRegex{
		Regex:         regexp.MustCompile("State transfer to.*left the group.*complete"),
		InternalRegex: regexp.MustCompile(regexIdx + " \\(" + regexNodeName + "\\): State transfer.*\\(left the group\\) complete"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			donor := utils.ShortNodeName(submatches[groupNodeName])
			delete(ctx.SSTs, donor)
			return ctx, types.SimpleDisplayer(donor + utils.Paint(utils.RedText, " synced ??(node left)"))
		},
	},

	"RegexSSTFailedUnknown": &types.LogRegex{
		Regex:         regexp.MustCompile("State transfer to.*left the group.*failed"),
		InternalRegex: regexp.MustCompile(regexIdx + " \\(" + regexNodeName + "\\): State transfer.*\\(left the group\\) failed"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			donor := utils.ShortNodeName(submatches[groupNodeName])
			delete(ctx.SSTs, donor)
			return ctx, types.SimpleDisplayer(donor + utils.Paint(utils.RedText, " failed to sync ??(node left)"))
		},
	},

	"RegexSSTStateTransferFailed": &types.LogRegex{
		Regex:         regexp.MustCompile("State transfer to.*failed:"),
		InternalRegex: regexp.MustCompile(regexIdx + " \\(" + regexNodeName + "\\): State transfer to " + regexIdx + " \\(" + regexNodeName2 + "\\) failed"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			donor := utils.ShortNodeName(submatches[groupNodeName])
			joiner := utils.ShortNodeName(submatches[groupNodeName2])
			delete(ctx.SSTs, donor)
			return ctx, types.SimpleDisplayer(donor + utils.Paint(utils.RedText, " failed to sync ") + joiner)
		},
	},

	"RegexSSTError": &types.LogRegex{
		Regex: regexp.MustCompile("Process completed with error: wsrep_sst"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "SST error"))
		},
	},

	"RegexSSTInitiating": &types.LogRegex{
		Regex:         regexp.MustCompile("Initiating SST.IST transfer on DONOR side"),
		InternalRegex: regexp.MustCompile("DONOR side \\((?P<scriptname>[a-zA-Z0-9-_]*) --role 'donor' --address '" + regexNodeIP + ":(?P<sstport>[0-9]*)\\)"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			return ctx, types.SimpleDisplayer("init sst using " + submatches["scriptname"])
		},
	},

	"RegexSSTCancellation": &types.LogRegex{
		Regex: regexp.MustCompile("Initiating SST cancellation"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "former SST cancelled"))
		},
	},

	"RegexSSTProceeding": &types.LogRegex{
		Regex: regexp.MustCompile("Proceeding with SST"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("JOINER")
			ctx.SetSSTTypeMaybe("SST")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "receiving SST"))
		},
	},

	"RegexSSTStreamingTo": &types.LogRegex{
		Regex:         regexp.MustCompile("Streaming the backup to"),
		InternalRegex: regexp.MustCompile("Streaming the backup to joiner at " + regexNodeIP),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			ctx.SetState("DONOR")
			joiner := submatches[groupNodeIP]

			return ctx, func(ctx types.LogCtx) string {
				return utils.Paint(utils.YellowText, "SST to ") + types.DisplayNodeSimplestForm(ctx, joiner)
			}
		},
	},

	"RegexISTReceived": &types.LogRegex{
		Regex: regexp.MustCompile("IST received"),

		// the UUID here is not from a node, it's a cluster state UUID, this is only used to ensure it's correctly parsed
		InternalRegex: regexp.MustCompile("IST received: " + regexUUID + ":" + regexSeqno),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			seqno := submatches[groupSeqno]
			return ctx, types.SimpleDisplayer(utils.Paint(utils.GreenText, "IST received") + "(seqno:" + seqno + ")")
		},
	},

	"RegexISTSender": &types.LogRegex{
		Regex: regexp.MustCompile("IST sender starting"),

		// TODO: sometimes, it's a hostname here
		InternalRegex: regexp.MustCompile("IST sender starting to serve " + regexNodeIPMethod + " sending [0-9]+-" + regexSeqno),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("DONOR")
			ctx.SetSSTTypeMaybe("IST")

			seqno := submatches[groupSeqno]
			node := submatches[groupNodeIP]

			return ctx, func(ctx types.LogCtx) string {
				return utils.Paint(utils.YellowText, "IST to ") + types.DisplayNodeSimplestForm(ctx, node) + "(seqno:" + seqno + ")"
			}
		},
	},

	"RegexISTReceiver": &types.LogRegex{
		Regex: regexp.MustCompile("Prepared IST receiver"),

		InternalRegex: regexp.MustCompile("Prepared IST receiver( for (?P<startingseqno>[0-9]+)-" + regexSeqno + ")?"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("JOINER")

			seqno := submatches[groupSeqno]
			msg := utils.Paint(utils.YellowText, "will receive ")

			startingseqno := submatches["startingseqno"]
			// if it's 0, it will go to SST without a doubt
			if startingseqno == "0" {
				ctx.SetSSTTypeMaybe("SST")
				msg += "SST"

				// not totally correct, but need more logs to get proper pattern
				// in some cases it does IST before going with SST
			} else {
				ctx.SetSSTTypeMaybe("IST")
				msg += "IST"
				if seqno != "" {
					msg += "(seqno:" + seqno + ")"
				}
			}
			return ctx, types.SimpleDisplayer(msg)
		},
	},

	"RegexFailedToPrepareIST": &types.LogRegex{
		Regex: regexp.MustCompile("Failed to prepare for incremental state transfer"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetSSTTypeMaybe("SST")
			return ctx, types.SimpleDisplayer("IST is not applicable")
		},
	},

	"RegexXtrabackupISTReceived": &types.LogRegex{
		Regex: regexp.MustCompile("xtrabackup_ist received from donor"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetSSTTypeMaybe("IST")
			return ctx, types.SimpleDisplayer("IST running")
		},
		Verbosity: types.DebugMySQL, // that one is not really helpful, except for tooling constraints
	},

	// could not find production examples yet, but it did exist in older version there also was "Bypassing state dump"
	"RegexBypassSST": &types.LogRegex{
		Regex: regexp.MustCompile("Bypassing SST"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			ctx.SetSSTTypeMaybe("IST")
			return ctx, types.SimpleDisplayer("IST will be used")
		},
	},

	"RegexSocatConnRefused": &types.LogRegex{
		Regex: regexp.MustCompile("E connect.*Connection refused"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "socat: connection refused"))
		},
	},

	// 2023-05-12T02:52:33.767132Z 0 [Note] [MY-000000] [WSREP-SST] Preparing the backup at /var/lib/mysql/sst-xb-tmpdir
	"RegexPreparingBackup": &types.LogRegex{
		Regex: regexp.MustCompile("Preparing the backup at"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer("preparing SST backup")
		},
	},

	"RegexTimeoutReceivingFirstData": &types.LogRegex{
		Regex: regexp.MustCompile("Possible timeout in receving first data from donor in gtid/keyring stage"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "timeout from donor in gtid/keyring stage"))
		},
	},

	"RegexWillNeverReceive": &types.LogRegex{
		Regex: regexp.MustCompile("Will never receive state. Need to abort"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "will never receive SST, aborting"))
		},
	},

	"RegexISTFailed": &types.LogRegex{
		Regex:         regexp.MustCompile("async IST sender failed to serve"),
		InternalRegex: regexp.MustCompile("IST sender failed to serve " + regexNodeIPMethod + ":.*asio error '.*: [0-9]+ \\((?P<error>[\\w\\s]+)\\)"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			node := submatches[groupNodeIP]
			istError := submatches["error"]

			return ctx, func(ctx types.LogCtx) string {
				return "IST to " + types.DisplayNodeSimplestForm(ctx, node) + utils.Paint(utils.RedText, " failed: ") + istError
			}
		},
	},
}

/*
2023-06-07T02:42:29.734960-06:00 0 [ERROR] WSREP: sst sent called when not SST donor, state SYNCED
2023-06-07T02:42:00.234711-06:00 0 [Warning] WSREP: Protocol violation. JOIN message sender 0.0 (node1) is not in state transfer (SYNCED). Message ignored.

)
*/
