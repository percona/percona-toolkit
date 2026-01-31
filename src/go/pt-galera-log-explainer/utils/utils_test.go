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

package utils

import "testing"

func TestStringsReplaceReverse(t *testing.T) {

	tests := []struct {
		inputS     string
		inputOld   string
		inputNew   string
		inputCount int
		expected   string
	}{
		{
			inputS:     "2022-22-22",
			inputOld:   "22",
			inputNew:   "XX",
			inputCount: 1,
			expected:   "2022-22-XX",
		},
		{
			inputS:     "2022-22-22",
			inputOld:   "22",
			inputNew:   "XX",
			inputCount: 2,
			expected:   "2022-XX-XX",
		},
		{
			inputS:     "2022-22-22",
			inputOld:   "22",
			inputNew:   "XX",
			inputCount: 3,
			expected:   "20XX-XX-XX",
		},
	}
	for _, test := range tests {
		if s := StringsReplaceReversed(test.inputS, test.inputOld, test.inputNew, test.inputCount); s != test.expected {
			t.Log("Expected", test.expected, "got", s)
			t.Fail()
		}
	}
}
