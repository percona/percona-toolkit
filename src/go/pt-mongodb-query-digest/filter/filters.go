// This program is copyright 2017-2026 Percona LLC and/or its affiliates.
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

package filter

import (
	"strings"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

type Filter func(proto.SystemProfile) bool

// This func receives a doc from the profiler and returns:
// true : the document must be considered
// false: the document must be skipped
func NewFilterByCollection(collectionsToSkip []string) func(proto.SystemProfile) bool {
	return func(doc proto.SystemProfile) bool {
		for _, collection := range collectionsToSkip {
			if strings.HasSuffix(doc.Ns, collection) {
				return false
			}
		}
		return true
	}
}
