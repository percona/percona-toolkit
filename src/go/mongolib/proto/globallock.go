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

type GlobalLock struct {
	ActiveClients *ActiveClients `bson:"activeClients"`
	CurrentQueue  *CurrentQueue  `bson:"currentQueue"`
	TotalTime     int64          `bson:"totalTime"`
}

type ActiveClients struct {
	Readers int64 `bson:"readers"`
	Total   int64 `bson:"total"`
	Writers int64 `bson:"writers"`
}

type CurrentQueue struct {
	Writers int64 `bson:"writers"`
	Readers int64 `bson:"readers"`
	Total   int64 `bson:"total"`
}
