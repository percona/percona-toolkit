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

import (
	"testing"

	"github.com/sirupsen/logrus"

	"github.com/percona/percona-toolkit/src/go/pt-pg-summary/models"
)

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

func TestCalcCountersDiff(t *testing.T) {
	counters := map[models.Name][]*models.Counters{
		"both": {
			{Datname: "both", Numbackends: 2, XactCommit: 10, BlksHit: 100, TempBytes: 4096},
			{Datname: "both", Numbackends: 3, XactCommit: 15, BlksHit: 160, TempBytes: 8192},
		},
		"created": {{Datname: "created", Numbackends: 1, XactCommit: 1}},
	}

	info := &PGInfo{logger: logrus.New()}
	info.calcCountersDiff(counters)

	if c, ok := counters["created"]; ok {
		t.Errorf("created is still in the counters with %d passes, want it removed", len(c))
	}
	both := counters["both"]
	if len(both) != 3 {
		t.Fatalf("both has %d counters, want 3", len(both))
	}
	if d := both[2]; d.Datname != "both" || d.Numbackends != 1 || d.XactCommit != 5 || d.BlksHit != 60 || d.TempBytes != 4096 {
		t.Errorf("diff = %+v, want Numbackends 1, XactCommit 5, BlksHit 60, TempBytes 4096", *d)
	}
}
