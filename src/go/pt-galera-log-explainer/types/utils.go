package types

import (
	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/utils"
	"github.com/rs/zerolog/log"
)

// Identifier is used to identify a node timeline.
// It will the column headers
// It will also impacts how logs are merged if we have multiple logs per nodes
//
// In order of preference: wsrep_node_name (or galera "node" name), hostname, ip, filepath
func Identifier(ctx LogCtx) string {
	if len(ctx.OwnNames) > 0 {
		return ctx.OwnNames[len(ctx.OwnNames)-1]
	}
	if len(ctx.OwnIPs) > 0 {
		return DisplayNodeSimplestForm(ctx, ctx.OwnIPs[len(ctx.OwnIPs)-1])
	}
	if len(ctx.OwnHashes) > 0 {
		if name, ok := ctx.HashToNodeName[ctx.OwnHashes[0]]; ok {
			return name
		}
		if ip, ok := ctx.HashToIP[ctx.OwnHashes[0]]; ok {
			return DisplayNodeSimplestForm(ctx, ip)
		}
	}
	return ctx.FilePath
}

// DisplayNodeSimplestForm is useful to get the most easily to read string for a given IP
// This only has impacts on display
// In order of preference: wsrep_node_name (or galera "node" name), hostname, ip
func DisplayNodeSimplestForm(ctx LogCtx, ip string) string {
	if nodename, ok := ctx.IPToNodeName[ip]; ok {
		s := utils.ShortNodeName(nodename)
		log.Debug().Str("ip", ip).Str("simplestform", s).Str("from", "IPToNodeName").Msg("nodeSimplestForm")
		return s
	}

	for hash, storedip := range ctx.HashToIP {
		if ip == storedip {
			if nodename, ok := ctx.HashToNodeName[hash]; ok {
				s := utils.ShortNodeName(nodename)
				log.Debug().Str("ip", ip).Str("simplestform", s).Str("from", "HashToNodeName").Msg("nodeSimplestForm")
				return s
			}
		}
	}
	if hostname, ok := ctx.IPToHostname[ip]; ok {
		log.Debug().Str("ip", ip).Str("simplestform", hostname).Str("from", "IPToHostname").Msg("nodeSimplestForm")
		return hostname
	}
	log.Debug().Str("ip", ip).Str("simplestform", ip).Str("from", "default").Msg("nodeSimplestForm")
	return ip
}
