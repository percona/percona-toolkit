// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
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

package proto

type TimeMs struct {
	WriteToDataFiles   float64 `bson:"writeToDataFiles"`
	WriteToJournal     float64 `bson:"writeToJournal"`
	Commits            float64 `bson:"commits"`
	CommitsInWriteLock float64 `bson:"commitsInWriteLock"`
	Dt                 float64 `bson:"dt"`
	PrepLogBuffer      float64 `bson:"prepLogBuffer"`
	RemapPrivateView   float64 `bson:"remapPrivateView"`
}

type Dur struct {
	TimeMs             *TimeMs `bson:"timeMs"`
	WriteToDataFilesMB float64 `bson:"writeToDataFilesMB"`
	Commits            float64 `bson:"commits"`
	CommitsInWriteLock float64 `bson:"commitsInWriteLock"`
	Compression        float64 `bson:"compression"`
	EarlyCommits       float64 `bson:"earlyCommits"`
	JournaledMB        float64 `bson:"journaledMB"`
}
