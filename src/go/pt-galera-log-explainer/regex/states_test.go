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
	"testing"
)

func TestStatesRegex(t *testing.T) {
	tests := []regexTest{

		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Shifting OPEN -> CLOSED (TO: 1922878)",
			expected: regexTestState{
				State: "CLOSED",
			},
			expectedOut: "OPEN -> CLOSED",
			key:         "RegexShift",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Shifting SYNCED -> DONOR/DESYNCED (TO: 21582507)",
			expected: regexTestState{
				State: "DONOR",
			},
			expectedOut: "SYNCED -> DONOR",
			key:         "RegexShift",
		},
		{
			log: "2001-01-01T01:01:01.000000Z 0 [Note] WSREP: Shifting DONOR/DESYNCED -> JOINED (TO: 21582507)",
			expected: regexTestState{
				State: "JOINED",
			},
			expectedOut: "DESYNCED -> JOINED",
			key:         "RegexShift",
		},

		{
			log: "2001-01-01 01:01:01 140446385440512 [Note] WSREP: Restored state OPEN -> SYNCED (72438094)",
			expected: regexTestState{
				State: "SYNCED",
			},
			expectedOut: "(restored)OPEN -> SYNCED",
			key:         "RegexRestoredState",
		},
	}

	iterateRegexTest(t, StatesMap, tests)
}
