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

// EventCategory groups events for CLI filters (--elections, --replication, ...).
type EventCategory string

const (
	CatNode        EventCategory = "node"
	CatRole        EventCategory = "role"
	CatTopology    EventCategory = "topology"
	CatReplication EventCategory = "replication"
	CatFailure     EventCategory = "failure"
	CatSharding    EventCategory = "sharding"
	CatPerformance EventCategory = "performance"
	CatCorrelation EventCategory = "correlation"
	CatAnomaly     EventCategory = "anomaly"
)

// EventStatus is a coarse outcome for automation / sorting.
type EventStatus string

const (
	StatusInfo    EventStatus = "INFO"
	StatusSuccess EventStatus = "SUCCESS"
	StatusWarn    EventStatus = "WARN"
	StatusFailure EventStatus = "FAILURE"
	StatusUnknown EventStatus = "UNKNOWN"
)

// StructuredEvent is a normalized cluster event for timeline output.
type StructuredEvent struct {
	Time       time.Time     `json:"time"`
	Node       string        `json:"node"`
	HostPort   string        `json:"host_port"`
	EventType  string        `json:"event_type"`
	Status     EventStatus   `json:"status"`
	Details    string        `json:"details"`
	Category   EventCategory `json:"category"`
	SourceFile string        `json:"source_file"`
	Raw        string        `json:"raw,omitempty"`
	Anomaly    string        `json:"anomaly,omitempty"`
	SequenceID string        `json:"sequence_id,omitempty"`
}
