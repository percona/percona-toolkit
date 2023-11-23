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
func Identifier(logCtx LogCtx, date time.Time) string {
	if len(logCtx.OwnNames) > 0 {
		return logCtx.OwnNames[len(logCtx.OwnNames)-1]
	}
	if len(logCtx.OwnIPs) > 0 {
		return translate.SimplestInfoFromIP(logCtx.OwnIPs[len(logCtx.OwnIPs)-1], date)
	}
	for _, hash := range logCtx.OwnHashes {
		if out := translate.SimplestInfoFromHash(hash, date); out != hash {
			return out
		}
	}
	return logCtx.FilePath
}
