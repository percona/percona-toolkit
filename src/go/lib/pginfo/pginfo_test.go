// This program is copyright 2019-2026 Percona LLC and/or its affiliates.
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

package pginfo

import "testing"

func TestParseServerVersion(t *testing.T) {
	for _, tc := range []struct {
		num  string
		want string
	}{
		{"90624", "9.6.24"},
		{"100023", "10.23.0"},
		{"120000", "12.0.0"},
		{"180006", "18.6.0"},
	} {
		v, err := parseServerVersion(tc.num)
		if err != nil {
			t.Errorf("parseServerVersion(%q): %s", tc.num, err)
			continue
		}
		if got := v.String(); got != tc.want {
			t.Errorf("parseServerVersion(%q) = %s, want %s", tc.num, got, tc.want)
		}
	}
}

func TestParseServerVersionRejectsGarbage(t *testing.T) {
	for _, num := range []string{"", "abc", "18.6"} {
		if v, err := parseServerVersion(num); err == nil {
			t.Errorf("parseServerVersion(%q) = %s, want an error", num, v)
		}
	}
}
