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

package types

import (
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-mongo-log-explainer/translate"
)

// Identifier picks a column header key for a node's timeline (hostname, listen port, IP, etc.).
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
