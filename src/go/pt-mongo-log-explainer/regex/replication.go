// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package regex

import (
	"regexp"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/types"
)

func init() {
	setType(types.ReplicationRegexType, ReplicationMap)
}

// ReplicationMap holds replication / initial-sync / oplog events.
var ReplicationMap = types.RegexMap{
	"RegexInitialSync": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)initial sync`),
		InternalRegex: regexp.MustCompile(`(?i)initial sync`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer("initial sync")
		},
		Verbosity: types.Info,
	},

	"RegexInitialSyncComplete": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)initial sync complete|finished initial sync`),
		InternalRegex: regexp.MustCompile(`(?i)initial sync complete|finished initial sync`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer("initial sync done")
		},
		Verbosity: types.Info,
	},

	"RegexOplogApplication": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)oplog|replication batch|Applying batch`),
		InternalRegex: regexp.MustCompile(`(?i)(oplog|replication batch|Applying batch)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer("oplog apply")
		},
		Verbosity: types.DebugContext,
	},

	"RegexResync": &types.LogRegex{
		Regex:         regexp.MustCompile(`(?i)resync|resync requested|full sync`),
		InternalRegex: regexp.MustCompile(`(?i)(resync|full sync)`),
		Handler: func(_ map[string]string, logCtx types.LogCtx, _ string, _ time.Time) (types.LogCtx, types.LogDisplayer) {
			return logCtx, types.SimpleDisplayer("resync")
		},
		Verbosity: types.Info,
	},
}
