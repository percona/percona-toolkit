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

type ShardStas struct {
	Ns                string   `json:"ns"`
	Count             int64    `json:"count"`
	Size              int64    `json:"size"`
	AvgObjSize        int64    `json:"avgObjSize"`
	NumExtents        int64    `json:"numExtents"`
	StorageSize       int64    `json:"storageSize"`
	LastExtentSize    int64    `json:"lastExtentSize"`
	PaddingFactor     int64    `json:"paddingFactor"`
	PaddingFactorNote string   `json:"paddingFactorNote"`
	UserFlags         int64    `json:"userFlags"`
	Capped            bool     `json:"capped"`
	Nindexes          int64    `json:"nindexes"`
	IndexDetails      struct{} `json:"indexDetails"`
	TotalIndexSize    int64    `json:"totalIndexSize"`
	IndexSizes        struct {
		ID       int64 `json:"_id_"`
		IDHashed int64 `json:"_id_hashed"`
	} `json:"indexSizes"`
	Ok int `json:"ok"`
}

type CollStats struct {
	Sharded           bool   `json:"sharded"`
	PaddingFactorNote string `json:"paddingFactorNote"`
	UserFlags         int64  `json:"userFlags"`
	Capped            bool   `json:"capped"`
	Ns                string `json:"ns"`
	Count             int64  `json:"count"`
	NumExtents        int64  `json:"numExtents"`
	Size              int64  `json:"size"`
	StorageSize       int64  `json:"storageSize"`
	TotalIndexSize    int64  `json:"totalIndexSize"`
	IndexSizes        struct {
		ID       int `json:"_id_"`
		IDHashed int `json:"_id_hashed"`
	} `json:"indexSizes"`
	AvgObjSize int64                `json:"avgObjSize"`
	Nindexes   int64                `json:"nindexes"`
	Nchunks    int64                `json:"nchunks"`
	Shards     map[string]ShardStas `json:"shards"`
	Ok         int64                `json:"ok"`
}
