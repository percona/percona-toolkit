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
	"testing"
)

func TestIsDuplicatedEvent(t *testing.T) {

	tests := []struct {
		name          string
		inputbase     LogInfo
		inputprevious LogInfo
		inputcurrent  LogInfo
		expected      bool
	}{
		{
			name:          "different regex, same output",
			inputbase:     LogInfo{RegexUsed: "some regex", displayer: SimpleDisplayer("")},
			inputprevious: LogInfo{RegexUsed: "some other regex", displayer: SimpleDisplayer("")},
			inputcurrent:  LogInfo{RegexUsed: "yet another regex", displayer: SimpleDisplayer("")},
			expected:      false,
		},
		{
			name:          "same regex, different output",
			inputbase:     LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("out1")},
			inputprevious: LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("out2")},
			inputcurrent:  LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("out3")},
			expected:      false,
		},
		{
			name:          "not enough duplication yet",
			inputbase:     LogInfo{RegexUsed: "another regex", displayer: SimpleDisplayer("")},
			inputprevious: LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("same")},
			inputcurrent:  LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("same")},
			expected:      false,
		},
		{
			name:          "duplicated",
			inputbase:     LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("same")},
			inputprevious: LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("same")},
			inputcurrent:  LogInfo{RegexUsed: "same regex", displayer: SimpleDisplayer("same")},
			expected:      true,
		},
	}

	for _, test := range tests {
		out := test.inputcurrent.IsDuplicatedEvent(test.inputbase, test.inputprevious)
		if out != test.expected {
			t.Fatalf("%s failed: expected %v, got %v", test.name, test.expected, out)
		}
	}

}
