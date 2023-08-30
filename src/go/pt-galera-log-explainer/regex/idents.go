package regex

import (
	"regexp"
	"strconv"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
)

func init() {
	init_add_regexes()
	setType(types.IdentRegexType, IdentsMap)
}

var IdentsMap = types.RegexMap{
	// sourceNode is to identify from which node this log was taken
	"RegexSourceNode": &types.LogRegex{
		Regex:         regexp.MustCompile("(local endpoint for a connection, blacklisting address)|(points to own listening address, blacklisting)"),
		InternalRegex: regexp.MustCompile("\\(" + regexNodeHash + ", '.+'\\).+" + regexNodeIPMethod),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			ip := submatches[groupNodeIP]
			ctx.AddOwnIP(ip)
			return ctx, types.SimpleDisplayer(ip + " is local")
		},
		Verbosity: types.DebugMySQL,
	},

	// 2022-12-18T01:03:17.950545Z 0 [Note] [MY-000000] [Galera] Passing config to GCS: base_dir = /var/lib/mysql/; base_host = 127.0.0.1;
	"RegexBaseHost": &types.LogRegex{
		Regex:         regexp.MustCompile("base_host"),
		InternalRegex: regexp.MustCompile("base_host = " + regexNodeIP),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			ip := submatches[groupNodeIP]
			ctx.AddOwnIP(ip)
			return ctx, types.SimpleDisplayer(ctx.OwnIPs[len(ctx.OwnIPs)-1] + " is local")
		},
		Verbosity: types.DebugMySQL,
	},

	//        0: 015702fc-32f5-11ed-a4ca-267f97316394, node-1
	//	      1: 08dd5580-32f7-11ed-a9eb-af5e3d01519e, garb
	// TO *never* DO: store indexes to later search for them using SST infos and STATES EXCHANGES logs. EDIT: is definitely NOT reliable
	"RegexMemberAssociations": &types.LogRegex{
		Regex:         regexp.MustCompile("[0-9]: [a-z0-9]+-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]+, [a-zA-Z0-9-_]+"),
		InternalRegex: regexp.MustCompile(regexIdx + ": " + regexUUID + ", " + regexNodeName),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			idx := submatches[groupIdx]
			hash := submatches[groupUUID]
			nodename := utils.ShortNodeName(submatches[groupNodeName])

			// nodenames are truncated after 32 characters ...
			if len(nodename) == 31 {
				return ctx, nil
			}
			shorthash := utils.UUIDToShortUUID(hash)
			ctx.HashToNodeName[shorthash] = nodename

			if ctx.MyIdx == idx && (ctx.IsPrimary() || ctx.MemberCount == 1) {
				ctx.AddOwnHash(shorthash)
				ctx.AddOwnName(nodename)
			}

			return ctx, types.SimpleDisplayer(shorthash + " is " + nodename)
		},
		Verbosity: types.DebugMySQL,
	},

	"RegexMemberCount": &types.LogRegex{
		Regex:         regexp.MustCompile("members.[0-9]+.:"),
		InternalRegex: regexp.MustCompile(regexMembers),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			members := submatches[groupMembers]

			membercount, err := strconv.Atoi(members)
			if err != nil {
				return ctx, nil
			}
			ctx.MemberCount = membercount

			return ctx, types.SimpleDisplayer("view member count: " + members)
		},
		Verbosity: types.DebugMySQL,
	},

	// My UUID: 6938f4ae-32f4-11ed-be8d-8a0f53f88872
	"RegexOwnUUID": &types.LogRegex{
		Regex:         regexp.MustCompile("My UUID"),
		InternalRegex: regexp.MustCompile("My UUID: " + regexUUID),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			shorthash := utils.UUIDToShortUUID(submatches[groupUUID])

			ctx.AddOwnHash(shorthash)

			return ctx, types.SimpleDisplayer(shorthash + " is local")
		},
		Verbosity: types.DebugMySQL,
	},

	// 2023-01-06T06:59:26.527748Z 0 [Note] WSREP: (9509c194, 'tcp://0.0.0.0:4567') turning message relay requesting on, nonlive peers:
	"RegexOwnUUIDFromMessageRelay": &types.LogRegex{
		Regex:         regexp.MustCompile("turning message relay requesting"),
		InternalRegex: regexp.MustCompile("\\(" + regexNodeHash + ", '" + regexNodeIPMethod + "'\\)"),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			hash := submatches[groupNodeHash]
			ctx.AddOwnHash(hash)

			return ctx, types.SimpleDisplayer(hash + " is local")
		},
		Verbosity: types.DebugMySQL,
	},

	// 2023-01-06T07:05:35.693861Z 0 [Note] WSREP: New COMPONENT: primary = yes, bootstrap = no, my_idx = 0, memb_num = 2
	"RegexMyIDXFromComponent": &types.LogRegex{
		Regex:         regexp.MustCompile("New COMPONENT:"),
		InternalRegex: regexp.MustCompile("New COMPONENT:.*my_idx = " + regexIdx),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {

			idx := submatches[groupIdx]
			ctx.MyIdx = idx
			return ctx, types.SimpleDisplayer("my_idx=" + idx)
		},
		Verbosity: types.DebugMySQL,
	},

	/*

			can't be trusted, from actual log:
			View:
		  id: <some cluster uuid>:<seqno>
		  status: primary
		  protocol_version: 4
		  capabilities: MULTI-MASTER, CERTIFICATION, PARALLEL_APPLYING, REPLAY, ISOLATION, PAUSE, CAUSAL_READ, INCREMENTAL_WS, UNORDERED, PREORDERED, STREAMING, NBO
		  final: no
		  own_index: 1
		  members(3):
		        0: <some uuid>, node0
		        1: <some uuid>, node1
		        2: <some uuid>, node2
		=================================================
		2023-05-28T21:18:23.184707-05:00 2 [Note] [MY-000000] [WSREP] wsrep_notify_cmd is not defined, skipping notification.
		2023-05-28T21:18:23.193459-05:00 0 [Note] [MY-000000] [Galera] STATE EXCHANGE: sent state msg: <cluster uuid>
		2023-05-28T21:18:23.195777-05:00 0 [Note] [MY-000000] [Galera] STATE EXCHANGE: got state msg: <cluster uuid> from 0 (node1)
		2023-05-28T21:18:23.195805-05:00 0 [Note] [MY-000000] [Galera] STATE EXCHANGE: got state msg: <cluster uuid> from 1 (node2)


				"RegexOwnNameFromStateExchange": &types.LogRegex{
					Regex:         regexp.MustCompile("STATE EXCHANGE: got state msg"),
					InternalRegex: regexp.MustCompile("STATE EXCHANGE:.* from " + regexIdx + " \\(" + regexNodeName + "\\)"),
					Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
						r, err := internalRegexSubmatch(internalRegex, log)
						if err != nil {
							return ctx, nil
						}

						idx := submatches[groupIdx]
						name := submatches[groupNodeName]
						if idx != ctx.MyIdx {
							return ctx, types.SimpleDisplayer("name(" + name + ") from unknown idx")
						}

						if ctx.State == "NON-PRIMARY" {
							return ctx, types.SimpleDisplayer("name(" + name + ") can't be trusted as it's non-primary")
						}

						ctx.AddOwnName(name)
						return ctx, types.SimpleDisplayer("local name:" + name)
					},
					Verbosity: types.DebugMySQL,
				},
	*/
}

func init_add_regexes() {
	// 2023-01-06T07:05:34.035959Z 0 [Note] WSREP: (9509c194, 'tcp://0.0.0.0:4567') connection established to 838ebd6d tcp://ip:4567
	IdentsMap["RegexOwnUUIDFromEstablished"] = &types.LogRegex{
		Regex:         regexp.MustCompile("connection established to"),
		InternalRegex: IdentsMap["RegexOwnUUIDFromMessageRelay"].InternalRegex,
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return IdentsMap["RegexOwnUUIDFromMessageRelay"].Handler(submatches, ctx, log)
		},
		Verbosity: types.DebugMySQL,
	}

	IdentsMap["RegexOwnIndexFromView"] = &types.LogRegex{
		Regex:         regexp.MustCompile("own_index:"),
		InternalRegex: regexp.MustCompile("own_index: " + regexIdx),
		Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
			return IdentsMap["RegexMyIDXFromComponent"].Handler(submatches, ctx, log)
		},
		Verbosity: types.DebugMySQL,
	}

	// 2023-01-06T07:05:35.698869Z 7 [Note] WSREP: New cluster view: global state: 00000000-0000-0000-0000-000000000000:0, view# 10: Primary, number of nodes: 2, my index: 0, protocol version 3
	// WARN: my index seems to always be 0 on this log on certain version. It had broken some nodenames
	/*
		IdentsMap["RegexMyIDXFromClusterView"] = &types.LogRegex{
			Regex:         regexp.MustCompile("New cluster view:"),
			InternalRegex: regexp.MustCompile("New cluster view:.*my index: " + regexIdx + ","),
			Handler: func(submatches map[string]string, ctx types.LogCtx, log string) (types.LogCtx, types.LogDisplayer) {
				return IdentsMap["RegexMyIDXFromComponent"].Handler(internalRegex, ctx, log)
			},
			Verbosity: types.DebugMySQL,
		}
	*/
}
