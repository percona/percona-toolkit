// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
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

package main

import (
	"strings"
)

func sectionBetweenHeaders(out, title string) string {
	start := strings.Index(out, "\n"+header(title)+"\n")
	if start < 0 {
		return ""
	}

	end := strings.Index(out[start+1:], "\n# ")
	if end < 0 {
		return out[start:]
	}

	return out[start : start+1+end]
}
