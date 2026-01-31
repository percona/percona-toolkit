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

import "regexp"

var RegexOperatorFileType = regexp.MustCompile(`\"file\":\"/([a-z]+/)+(?P<filetype>[a-z._-]+.log)\"}$`)
var RegexOperatorShellDebugFileType = regexp.MustCompile(`^\+`)

func FileType(line string, operator bool) string {
	if !operator {
		// if not operator, we can't really guess
		return "error.log"
	}
	r, err := internalRegexSubmatch(RegexOperatorFileType, line)
	if err != nil {
		if RegexOperatorShellDebugFileType.MatchString(line) {
			return "operator shell"
		}
		return ""
	}
	t := r[RegexOperatorFileType.SubexpIndex("filetype")]
	switch t {
	case "mysqld.post.processing.log":
		return "post.processing.log"
	case "wsrep_recovery_verbose.log":
		return "recovery.log"
	case "mysqld-error.log":
		return "error.log"
	case "innobackup.backup.log":
		return "backup.log"
	default:
		return t
	}
}
