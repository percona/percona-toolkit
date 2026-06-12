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

import (
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

type OplogEntry struct {
	Name    string
	Options struct {
		Capped      bool
		Size        int64
		AutoIndexId bool
	}
}

type OplogInfo struct {
	Hostname      string
	Size          int64
	UsedMB        int64
	TimeDiff      time.Duration
	TimeDiffHours float64
	Running       string // TimeDiffHours in human readable format
	TFirst        time.Time
	TLast         time.Time
	Now           time.Time
	ElectionTime  time.Time
}

type OpLogs []OplogInfo

func (s OpLogs) Len() int {
	return len(s)
}

func (s OpLogs) Swap(i, j int) {
	s[i], s[j] = s[j], s[i]
}

func (s OpLogs) Less(i, j int) bool {
	return s[i].TimeDiffHours < s[j].TimeDiffHours
}

type OplogRow struct {
	Timestamp primitive.Timestamp `bson:"ts,omitempty"`
	HistoryId int64               `bson:"h,omitempty"`
	Version   int64               `bson:"v,omitempty"`
	Operation string              `bson:"op,omitempty"`
	Namespace string              `bson:"ns,omitempty"`
	Object    bson.D              `bson:"o,omitempty"`
	Query     bson.D              `bson:"o2,omitempty"`
}

type OplogColStats struct {
	NumExtents        int
	IndexDetails      bson.M
	Nindexes          int
	TotalIndexSize    int64
	Size              int64
	PaddingFactorNote string
	Capped            bool
	MaxSize           int64
	IndexSizes        bson.M
	GleStats          struct {
		LastOpTime time.Time
		ElectionId string
	} `bson:"$gleStats"`
	StorageSize    int64
	PaddingFactor  int64
	AvgObjSize     int64
	LastExtentSize int64
	UserFlags      int64
	Max            int64
	Ok             int
	Ns             string
	Count          int64
}
