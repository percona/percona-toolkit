package types

import (
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/translate"
)

// Identifier is used to identify a node timeline.
// It will the column headers
// It will also impacts how logs are merged if we have multiple logs per nodes
//
// In order of preference: wsrep_node_name (or galera "node" name), hostname, ip, filepath
func Identifier(ctx LogCtx, date time.Time) string {
	if len(ctx.OwnNames) > 0 {
		return ctx.OwnNames[len(ctx.OwnNames)-1]
	}
	if len(ctx.OwnIPs) > 0 {
		return translate.SimplestInfoFromIP(ctx.OwnIPs[len(ctx.OwnIPs)-1], date)
	}
	for _, hash := range ctx.OwnHashes {
		if out := translate.SimplestInfoFromHash(hash, date); out != hash {
			return out
		}
	}
	return ctx.FilePath
}
