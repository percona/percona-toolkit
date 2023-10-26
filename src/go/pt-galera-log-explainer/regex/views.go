package regex

import (
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/translate"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func init() {
	setType(types.ViewsRegexType, ViewsMap)
}

// "galera views" regexes
var ViewsMap = types.RegexMap{
	"RegexNodeEstablished": &types.LogRegex{
		Regex:         regexp.MustCompile("connection established"),
		InternalRegex: regexp.MustCompile("established to " + regexNodeHash + " " + regexNodeIPMethod),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			ip := submatches[groupNodeIP]
			hash := submatches[groupNodeHash]
			translate.AddHashToIP(hash, ip, date)
			if utils.SliceContains(ctx.OwnIPs, ip) {
				return ctx, nil
			}
			return ctx, types.FormatByHashDisplayer("%s established", hash, date)
		},
		Verbosity: types.DebugMySQL,
	},

	"RegexNodeJoined": &types.LogRegex{
		Regex:         regexp.MustCompile("declaring .* stable"),
		InternalRegex: regexp.MustCompile("declaring " + regexNodeHash + " at " + regexNodeIPMethod),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			ip := submatches[groupNodeIP]
			hash := submatches[groupNodeHash]
			translate.AddHashToIP(hash, ip, date)
			translate.AddIPToMethod(ip, submatches[groupMethod], date)
			return ctx, types.FormatByHashDisplayer("%s"+utils.Paint(utils.GreenText, " joined"), hash, date)
		},
	},

	"RegexNodeLeft": &types.LogRegex{
		Regex:         regexp.MustCompile("forgetting"),
		InternalRegex: regexp.MustCompile("forgetting " + regexNodeHash + " \\(" + regexNodeIPMethod),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			ip := submatches[groupNodeIP]
			hash := submatches[groupNodeHash]
			translate.AddHashToIP(hash, ip, date)
			translate.AddIPToMethod(ip, submatches[groupMethod], date)
			return ctx, types.FormatByHashDisplayer("%s"+utils.Paint(utils.RedText, " left"), hash, date)
		},
	},

	// New COMPONENT: primary = yes, bootstrap = no, my_idx = 1, memb_num = 5
	"RegexNewComponent": &types.LogRegex{
		Regex:         regexp.MustCompile("New COMPONENT:"),
		InternalRegex: regexp.MustCompile("New COMPONENT: primary = (?P<primary>.+), bootstrap = (?P<bootstrap>.*), my_idx = .*, memb_num = (?P<memb_num>[0-9]{1,2})"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			primary := submatches["primary"] == "yes"
			membNum := submatches["memb_num"]
			bootstrap := submatches["bootstrap"] == "yes"
			memberCount, err := strconv.Atoi(membNum)
			if err != nil {
				return ctx, nil
			}

			ctx.MemberCount = memberCount
			if primary {
				// we don't always store PRIMARY because we could have found DONOR/JOINER/SYNCED/DESYNCED just earlier
				// and we do not want to override these as they have more value
				if !ctx.IsPrimary() {
					ctx.SetState("PRIMARY")
				}
				msg := utils.Paint(utils.GreenText, "PRIMARY") + "(n=" + membNum + ")"
				if bootstrap {
					msg += ",bootstrap"
				}
				return ctx, types.SimpleDisplayer(msg)
			}

			ctx.SetState("NON-PRIMARY")
			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "NON-PRIMARY") + "(n=" + membNum + ")")
		},
	},

	"RegexNodeSuspect": &types.LogRegex{
		Regex:         regexp.MustCompile("suspecting node"),
		InternalRegex: regexp.MustCompile("suspecting node: " + regexNodeHash),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			hash := submatches[groupNodeHash]

			return ctx, types.FormatByHashDisplayer("%s"+utils.Paint(utils.YellowText, " suspected to be down"), hash, date)
		},
	},

	"RegexNodeChangedIdentity": &types.LogRegex{
		Regex:         regexp.MustCompile("remote endpoint.*changed identity"),
		InternalRegex: regexp.MustCompile("remote endpoint " + regexNodeIPMethod + " changed identity " + regexNodeHash + " -> " + strings.Replace(regexNodeHash, groupNodeHash, groupNodeHash+"2", -1)),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {

			hash := utils.UUIDToShortUUID(submatches[groupNodeHash])
			hash2 := utils.UUIDToShortUUID(submatches[groupNodeHash+"2"])
			if ip := translate.GetIPFromHash(hash); ip != "" {
				translate.AddHashToIP(hash2, ip, date)
			}
			return ctx, types.FormatByHashDisplayer("%s"+utils.Paint(utils.YellowText, " changed identity"), hash, date)
		},
	},

	"RegexWsrepUnsafeBootstrap": &types.LogRegex{
		Regex: regexp.MustCompile("ERROR.*not be safe to bootstrap"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "not safe to bootstrap"))
		},
	},
	"RegexWsrepConsistenctyCompromised": &types.LogRegex{
		Regex: regexp.MustCompile(".ode consistency compromi.ed"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			ctx.SetState("CLOSED")

			return ctx, types.SimpleDisplayer(utils.Paint(utils.RedText, "consistency compromised"))
		},
	},
	"RegexWsrepNonPrimary": &types.LogRegex{
		Regex: regexp.MustCompile("failed to reach primary view"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer("received " + utils.Paint(utils.RedText, "non primary"))
		},
	},

	"RegexBootstrap": &types.LogRegex{
		Regex: regexp.MustCompile("gcomm: bootstrapping new group"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "bootstrapping"))
		},
	},

	"RegexSafeToBoostrapSet": &types.LogRegex{
		Regex: regexp.MustCompile("safe_to_bootstrap: 1"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "safe_to_bootstrap: 1"))
		},
	},
	"RegexNoGrastate": &types.LogRegex{
		Regex: regexp.MustCompile("Could not open state file for reading.*grastate.dat"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "no grastate.dat file"))
		},
	},
	"RegexBootstrapingDefaultState": &types.LogRegex{
		Regex: regexp.MustCompile("Bootstraping with default state"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string, date time.Time) (types.LogCtx, types.LogDisplayer) {
			return ctx, types.SimpleDisplayer(utils.Paint(utils.YellowText, "bootstrapping(empty grastate)"))
		},
	},
}

/*

2022-11-29T23:34:51.820009-05:00 0 [Warning] [MY-000000] [Galera] Could not find peer: c0ff4085-5ad7-11ed-8b74-cfeec74147fe

2022-12-07  1:00:06 0 [Note] WSREP: Member 0.0 (node) synced with group.


2021-03-25T21:58:13.570928Z 0 [Warning] WSREP: no nodes coming from prim view, prim not possible
2021-03-25T21:58:13.855983Z 0 [Warning] WSREP: Quorum: No node with complete state:



2021-04-22T08:01:05.000581Z 0 [Warning] WSREP: Failed to report last committed 66328091, -110 (Connection timed out)


input_map=evs::input_map: {aru_seq=8,safe_seq=8,node_index=node: {idx=0,range=[9,8],safe_seq=8} node: {idx=1,range=[9,8],safe_seq=8} },
fifo_seq=4829086170,
last_sent=8,
known:
17a2e064 at tcp://ip:4567
{o=0,s=1,i=0,fs=-1,}
470a6438 at tcp://ip:4567
{o=1,s=0,i=0,fs=4829091361,jm=
{v=0,t=4,ut=255,o=1,s=8,sr=-1,as=8,f=4,src=470a6438,srcvid=view_id(REG,470a6438,24),insvid=view_id(UNKNOWN,00000000,0),ru=00000000,r=[-1,-1],fs=4829091361,nl=(
        17a2e064, {o=0,s=1,e=0,ls=-1,vid=view_id(REG,00000000,0),ss=-1,ir=[-1,-1],}
        470a6438, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,470a6438,24),ss=8,ir=[9,8],}
        6548cf50, {o=1,s=1,e=0,ls=-1,vid=view_id(REG,17a2e064,24),ss=12,ir=[13,12],}
        8b0c0f77, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,470a6438,24),ss=8,ir=[9,8],}
        d4397932, {o=0,s=1,e=0,ls=-1,vid=view_id(REG,00000000,0),ss=-1,ir=[-1,-1],}
)
},
}
6548cf50 at tcp://ip:4567
{o=1,s=1,i=0,fs=-1,jm=
{v=0,t=4,ut=255,o=1,s=12,sr=-1,as=12,f=4,src=6548cf50,srcvid=view_id(REG,17a2e064,24),insvid=view_id(UNKNOWN,00000000,0),ru=00000000,r=[-1,-1],fs=4829165031,nl=(
        17a2e064, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,17a2e064,24),ss=12,ir=[13,12],}
        470a6438, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,00000000,0),ss=-1,ir=[-1,-1],}
        6548cf50, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,17a2e064,24),ss=12,ir=[13,12],}
        8b0c0f77, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,00000000,0),ss=-1,ir=[-1,-1],}
        d4397932, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,17a2e064,24),ss=12,ir=[13,12],}
)
},
}
8b0c0f77 at
{o=1,s=0,i=0,fs=-1,jm=
{v=0,t=4,ut=255,o=1,s=8,sr=-1,as=8,f=0,src=8b0c0f77,srcvid=view_id(REG,470a6438,24),insvid=view_id(UNKNOWN,00000000,0),ru=00000000,r=[-1,-1],fs=4829086170,nl=(
        17a2e064, {o=0,s=1,e=0,ls=-1,vid=view_id(REG,00000000,0),ss=-1,ir=[-1,-1],}
        470a6438, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,470a6438,24),ss=8,ir=[9,8],}
        6548cf50, {o=1,s=1,e=0,ls=-1,vid=view_id(REG,17a2e064,24),ss=12,ir=[13,12],}
        8b0c0f77, {o=1,s=0,e=0,ls=-1,vid=view_id(REG,470a6438,24),ss=8,ir=[9,8],}
        d4397932, {o=0,s=1,e=0,ls=-1,vid=view_id(REG,00000000,0),ss=-1,ir=[-1,-1],}
)
},
}
d4397932 at tcp://ip:4567
{o=0,s=1,i=0,fs=4685894552,}
 }

 Transport endpoint is not connected


 2023-03-31T08:05:57.964535Z 0 [Note] WSREP: handshake failed, my group: '<group>', peer group: '<bad group>'

 2023-04-04T22:35:23.487304Z 0 [Warning] [MY-000000] [Galera] Handshake failed: tlsv1 alert decrypt error

 2023-04-16T19:35:06.875877Z 0 [Warning] [MY-000000] [Galera] Action message in non-primary configuration from member 0

{"log":"2023-06-10T04:50:46.835491Z 0 [Note] [MY-000000] [Galera] going to give up, state dump for diagnosis:\nevs::proto(evs::proto(6d0345f5-bcc0, GATHER, view_id(REG,02e369be-8363,1046)), GATHER) {\ncurrent_view=Current view of cluster as seen by this node\nview (view_id(REG,02e369be-8363,1046)\nmemb {\n\t02e369be-8363,0\n\t49761f3d-bd34,0\n\t6d0345f5-bcc0,0\n\tb05443d1-96bf,0\n\tb05443d1-96c0,0\n\t}\njoined {\n\t}\nleft {\n\t}\npartitioned {\n\t}\n),\ninput_map=evs::input_map: {aru_seq=461,safe_seq=461,node_index=node: {idx=0,range=[462,461],safe_seq=461} node: {idx=1,range=[462,461],safe_seq=461} node: {idx=2,range=[462,461],safe_seq=461} node: {idx=3,range=[462,461],safe_seq=461} node: {idx=4,range=[462,461],safe_seq=461} },\nfifo_seq=221418422,\nlast_sent=461,\nknown:\n","file":"/var/lib/mysql/mysqld-error.log"}


[Warning] WSREP: FLOW message from member -12921743687968 in non-primary configuration. Ignored.

 0 [Note] [MY-000000] [Galera] (<hash>, 'tcp://0.0.0.0:4567') reconnecting to <hash (tcp://<ip>:4567), attempt 0


*/
