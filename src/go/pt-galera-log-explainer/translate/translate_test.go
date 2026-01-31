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

package translate

import (
	"testing"
	"time"
)

func TestAddHashToNodeName(t *testing.T) {
	hash1 := "somehash"
	name1 := "somename"
	ResetDB()
	ts1, _ := time.Parse(time.RFC3339, "2001-01-01T01:01:01")
	AddHashToNodeName(hash1, name1, ts1)
	if length := len(db.HashToNodeNames[hash1]); length != 1 {
		t.Errorf("incorrect hashtonodenames length: %d, expected 1", length)
		t.Fail()
	}
	name2 := "somename.with.a.fqdn.net"
	AddHashToNodeName(hash1, name2, ts1)
	if length := len(db.HashToNodeNames[hash1]); length != 1 {
		t.Errorf("incorrect hashtonodenames length: %d, expected 1", length)
		t.Fail()
	}
	name3 := "somename2.with.a.fqdn.net"
	AddHashToNodeName(hash1, name3, ts1)
	if length := len(db.HashToNodeNames[hash1]); length != 2 {
		t.Errorf("incorrect hashtonodenames length: %d, expected 2", length)
		t.Fail()
	}
}

func TestAddIPToNodeName(t *testing.T) {
	ip := "127.0.0.1"
	name1 := "somename"
	ResetDB()
	ts1, _ := time.Parse(time.RFC3339, "2001-01-01T01:01:01")
	AddIPToNodeName(ip, name1, ts1)
	if length := len(db.IPToNodeNames[ip]); length != 1 {
		t.Errorf("incorrect iptonodenames length: %d, expected 1", length)
		t.Fail()
	}
	name2 := "somename.with.a.fqdn.net"
	AddIPToNodeName(ip, name2, ts1)
	if length := len(db.IPToNodeNames[ip]); length != 1 {
		t.Errorf("incorrect iptonodenames length: %d, expected 1", length)
		t.Fail()
	}
	name3 := "somename2.with.a.fqdn.net"
	AddIPToNodeName(ip, name3, ts1)
	if length := len(db.IPToNodeNames[ip]); length != 2 {
		t.Errorf("incorrect iptonodenames length: %d, expected 2", length)
		t.Fail()
	}
}

func testMostAppropriateValueFromTS(t *testing.T) {
	tests := []struct {
		inputunits []translationUnit
		inputts    time.Time
		expected   string
	}{
		{
			inputunits: []translationUnit{
				translationUnit{Value: "value1", Timestamp: time.Date(2001, time.January, 1, 1, 1, 1, 0, time.UTC)},
				translationUnit{Value: "value2", Timestamp: time.Date(2001, time.January, 1, 3, 1, 1, 0, time.UTC)},
			},
			inputts:  time.Date(2001, time.January, 1, 2, 1, 1, 0, time.UTC),
			expected: "value1",
		},
		{
			inputunits: []translationUnit{
				translationUnit{Value: "value1", Timestamp: time.Date(2001, time.January, 1, 1, 1, 1, 0, time.UTC)},
				translationUnit{Value: "value2", Timestamp: time.Date(2001, time.January, 1, 3, 1, 1, 0, time.UTC)},
			},
			inputts:  time.Date(2001, time.January, 1, 4, 1, 1, 0, time.UTC),
			expected: "value2",
		},
		{
			inputunits: []translationUnit{
				translationUnit{Value: "value1", Timestamp: time.Date(2001, time.January, 1, 1, 1, 1, 0, time.UTC)},
				translationUnit{Value: "value2", Timestamp: time.Date(2001, time.January, 1, 3, 1, 1, 0, time.UTC)},
				translationUnit{Value: "value3", Timestamp: time.Date(2001, time.January, 1, 5, 1, 1, 0, time.UTC)},
			},
			inputts:  time.Date(2001, time.January, 1, 4, 1, 1, 0, time.UTC),
			expected: "value2",
		},
		{
			inputunits: []translationUnit{
				translationUnit{Value: "value1", Timestamp: time.Date(2001, time.January, 1, 1, 1, 1, 0, time.UTC)},
				translationUnit{Value: "value2", Timestamp: time.Date(2001, time.January, 1, 3, 1, 1, 0, time.UTC)},
			},
			inputts:  time.Date(2001, time.January, 1, 0, 1, 1, 0, time.UTC),
			expected: "value1",
		},
	}

	for i, test := range tests {
		out := mostAppropriateValueFromTS(test.inputunits, test.inputts)
		if out.Value != test.expected {
			t.Errorf("test %d, expected: %s, got: %s", i, test.expected, out)
		}
	}
}
