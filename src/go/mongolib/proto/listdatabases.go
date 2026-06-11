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

import "go.mongodb.org/mongo-driver/bson/primitive"

// CollectionEntry represents an entry for ListCollections
type CollectionEntry struct {
	Name    string `bson:"name"`
	Type    string `bson:"type"`
	Options struct {
		Capped      bool  `bson:"capped"`
		Size        int64 `bson:"size"`
		AutoIndexID bool  `bson:"autoIndexId"`
	} `bson:"options"`
	Info struct {
		ReadOnly bool             `bson:"readOnly"`
		UUID     primitive.Binary `bson:"uuid"`
	} `bson:"info"`
}
