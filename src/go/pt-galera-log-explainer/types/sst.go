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
