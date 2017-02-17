package proto

import (
	"time"

	"gopkg.in/mgo.v2/bson"
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
	TimeDiff      int64
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
	H  int64  `bson:"h"`
	V  int64  `bson:"v"`
	Op string `bson:"op"`
	O  bson.M `bson:"o"`
	Ts int64  `bson:"ts"`
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
		LastOpTime int64
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
