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

import "time"

type SST struct {
	Method             string
	Type               string
	Joiner             string
	Donor              string
	SelectionTimestamp *time.Time
}

// MustHaveHappenedLocally use the "selected x as donor" timestamp
// and compare it to the timestamp of donor/joiner wsrep status shift
// Usually, when it is selected, joiner/donor take a few milliseconds to shift their status
// This is the most solid way so far to correctly map donor and joiners when concurrents SSTs
// are running
func (sst SST) MustHaveHappenedLocally(shiftTimestamp time.Time) bool {
	if sst.SelectionTimestamp == nil {
		return false
	}
	return shiftTimestamp.Sub(*sst.SelectionTimestamp).Seconds() <= 0.01
}
