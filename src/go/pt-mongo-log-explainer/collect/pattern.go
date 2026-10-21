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

package collect

import "strings"

// GrepAlternation returns a PCRE alternation of literals for fast pre-filtering (grep -P).
func GrepAlternation() string {
	parts := []string{
		`election`, `primary`, `secondary`, `arbiter`, `rollback`, `heartbeat`,
		`initial sync`, `replSet`, `replica set`, `reconfig`, `stepped down`, `stepping down`,
		`mongos`, `chunk`, `balancer`, `migration`, `sharding`,
		`authentication failed`, `auth failed`, `network error`, `connection reset`,
		`MongoDB starting`, `waiting for connections`, `shutting down`, `now exiting`,
		`fatal`, `assertion`, `slow query`, `oplog`, `transition to`, `member is now in state`,
		`pid=`, `64-bit host=`, `db version`, `Replica Set Member State`,
		`"msg"`, `"c":"REPL"`, `"c":"SHARDING"`, `"c":"NETWORK"`, `"c":"CONN"`,
		`Changed sync source`, `sync source`, `oplog window`,
		`quorum`, `not enough`, `majority`,
		`not reachable`, `connection pool`, `socket exception`, `SocketException`,
		`DNS resolution`, `write concern`, `WriteConcernError`,
		`index build`, `exceeded time limit`, `MaxTimeMSExpired`,
		`cursor.*timed out`, `long-running`,
		`migration started`, `migration committed`, `migration aborted`,
		`balancer round`, `balancer enabled`, `balancer disabled`,
		`"c":"ELECTION"`, `"c":"REPL_HB"`, `"c":"INDEX"`,
	}
	var b strings.Builder
	for i, p := range parts {
		if i > 0 {
			b.WriteString(`|`)
		}
		b.WriteString(regexpQuoteMetaPCRE(p))
	}
	return b.String()
}

func regexpQuoteMetaPCRE(s string) string {
	// minimal escaping for alternation literals in PCRE
	r := strings.NewReplacer(
		`\`, `\\`,
		`.`, `\.`,
		`*`, `\*`,
		`+`, `\+`,
		`?`, `\?`,
		`|`, `\|`,
		`(`, `\(`,
		`)`, `\)`,
		`[`, `\[`,
		`]`, `\]`,
		`{`, `\{`,
		`}`, `\}`,
		`^`, `\^`,
		`$`, `\$`,
	)
	return r.Replace(s)
}
