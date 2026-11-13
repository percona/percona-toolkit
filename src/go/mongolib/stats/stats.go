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

package stats

import (
	"crypto/md5"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/montanaflynn/stats"
	"go.mongodb.org/mongo-driver/bson"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

const (
	planSummaryCollScan = "COLLSCAN"
)

type StatsError struct {
	error
}

func (e *StatsError) Error() string {
	if e == nil {
		return "<nil>"
	}

	return fmt.Sprintf("stats error: %s", e.error)
}

func (e *StatsError) Parent() error {
	return e.error
}

type StatsFingerprintError StatsError

// New creates new instance of stats with given Fingerprinter
func New(fingerprinter Fingerprinter) *Stats {
	s := &Stats{
		fingerprinter: fingerprinter,
	}

	s.Reset()
	return s
}

// Stats is a collection of MongoDB statistics
type Stats struct {
	// dependencies
	fingerprinter Fingerprinter

	// internal
	queryInfoAndCounters map[GroupKey]*QueryInfoAndCounters
	sync.RWMutex
}

// Reset clears the collection of statistics
func (s *Stats) Reset() {
	s.Lock()
	defer s.Unlock()

	s.queryInfoAndCounters = make(map[GroupKey]*QueryInfoAndCounters)
}

// Add adds proto.SystemProfile to the collection of statistics
func (s *Stats) Add(doc proto.SystemProfile) error {
	fp, err := s.fingerprinter.Fingerprint(doc)
	if err != nil {
		return &StatsFingerprintError{err}
	}
	var qiac *QueryInfoAndCounters
	var ok bool

	key := GroupKey{
		Operation:   fp.Operation,
		Fingerprint: fp.Fingerprint,
		Namespace:   fp.Namespace,
	}
	if qiac, ok = s.getQueryInfoAndCounters(key); !ok {
		query := proto.NewExampleQuery(doc)
		queryBson, err := bson.MarshalExtJSON(query, true, true)
		if err != nil {
			return err
		}
		qiac = &QueryInfoAndCounters{
			ID:          fmt.Sprintf("%x", md5.Sum([]byte(fmt.Sprintf("%s", key)))),
			Operation:   fp.Operation,
			Fingerprint: fp.Fingerprint,
			Namespace:   fp.Namespace,
			TableScan:   false,
			Query:       string(queryBson),
			PlanSummary: doc.PlanSummary,
			QueryHash:   doc.QueryHash,
			AppName:     doc.AppName,
			Client:      doc.Client,
			User:        strings.Split(doc.User, "@")[0],
			Comments:    doc.Comments,
		}
		s.setQueryInfoAndCounters(key, qiac)
	}
	qiac.Count++
	s.Lock()
	if qiac.PlanSummary == planSummaryCollScan {
		qiac.CollScanCount++
	}

	qiac.PlanSummary = strings.Split(qiac.PlanSummary, " ")[0]

	qiac.NReturned = append(qiac.NReturned, float64(doc.Nreturned))
	qiac.QueryTime = append(qiac.QueryTime, float64(doc.Millis))
	qiac.ResponseLength = append(qiac.ResponseLength, float64(doc.ResponseLength))
	if qiac.FirstSeen.IsZero() || qiac.FirstSeen.After(doc.Ts) {
		qiac.FirstSeen = doc.Ts
	}
	if qiac.LastSeen.IsZero() || qiac.LastSeen.Before(doc.Ts) {
		qiac.LastSeen = doc.Ts
	}

	if doc.DocsExamined > 0 {
		qiac.DocsExamined = append(qiac.DocsExamined, float64(doc.DocsExamined))
	}
	if doc.KeysExamined > 0 {
		qiac.KeysExamined = append(qiac.KeysExamined, float64(doc.KeysExamined))
	}
	if doc.Locks.Global.AcquireCount.ReadShared > 0 {
		qiac.LocksGlobalAcquireCountReadSharedCount++
		qiac.LocksGlobalAcquireCountReadShared += doc.Locks.Global.AcquireCount.ReadShared
	}
	if doc.Locks.Global.AcquireCount.WriteShared > 0 {
		qiac.LocksGlobalAcquireCountWriteSharedCount++
		qiac.LocksGlobalAcquireCountWriteShared += doc.Locks.Global.AcquireCount.WriteShared
	}
	if doc.Locks.Database.AcquireCount.ReadShared > 0 {
		qiac.LocksDatabaseAcquireCountReadSharedCount++
		qiac.LocksDatabaseAcquireCountReadShared += doc.Locks.Database.AcquireCount.ReadShared
	}
	if doc.Locks.Database.AcquireWaitCount.ReadShared > 0 {
		qiac.LocksDatabaseAcquireWaitCountReadSharedCount++
		qiac.LocksDatabaseAcquireWaitCountReadShared += doc.Locks.Database.AcquireWaitCount.ReadShared
	}
	if doc.Locks.Database.TimeAcquiringMicros.ReadShared > 0 {
		qiac.LocksDatabaseTimeAcquiringMicrosReadShared = append(qiac.LocksDatabaseTimeAcquiringMicrosReadShared, float64(doc.Locks.Database.TimeAcquiringMicros.ReadShared))
	}
	if doc.Locks.Collection.AcquireCount.ReadShared > 0 {
		qiac.LocksCollectionAcquireCountReadSharedCount++
		qiac.LocksCollectionAcquireCountReadShared += doc.Locks.Collection.AcquireCount.ReadShared
	}
	if doc.Storage.Data.BytesRead > 0 {
		qiac.StorageBytesRead = append(qiac.StorageBytesRead, float64(doc.Storage.Data.BytesRead))
	}
	if doc.Storage.Data.TimeReadingMicros > 0 {
		qiac.StorageTimeReadingMicros = append(qiac.StorageTimeReadingMicros, float64(doc.Storage.Data.TimeReadingMicros))
	}
	s.Unlock()

	return nil
}

// Queries returns all collected statistics
func (s *Stats) Queries() Queries {
	s.Lock()
	defer s.Unlock()

	keys := GroupKeys{}
	for key := range s.queryInfoAndCounters {
		keys = append(keys, key)
	}
	sort.Sort(keys)

	queries := []QueryInfoAndCounters{}
	for _, key := range keys {
		queries = append(queries, *s.queryInfoAndCounters[key])
	}
	return queries
}

func (s *Stats) getQueryInfoAndCounters(key GroupKey) (*QueryInfoAndCounters, bool) {
	s.RLock()
	defer s.RUnlock()

	v, ok := s.queryInfoAndCounters[key]
	return v, ok
}

func (s *Stats) setQueryInfoAndCounters(key GroupKey, value *QueryInfoAndCounters) {
	s.Lock()
	defer s.Unlock()

	s.queryInfoAndCounters[key] = value
}

// Queries is a slice of MongoDB statistics
type Queries []QueryInfoAndCounters

// CalcQueriesStats calculates QueryStats for given uptime
func (q Queries) CalcQueriesStats(uptime int64) []QueryStats {
	qs := []QueryStats{}
	tc := calcTotalCounters(q)

	for _, query := range q {
		queryStats := countersToStats(query, uptime, tc)
		qs = append(qs, queryStats)
	}

	return qs
}

// CalcTotalQueriesStats calculates total QueryStats for given uptime
func (q Queries) CalcTotalQueriesStats(uptime int64) QueryStats {
	tc := calcTotalCounters(q)

	totalQueryInfoAndCounters := aggregateCounters(q)
	totalStats := countersToStats(totalQueryInfoAndCounters, uptime, tc)

	return totalStats
}

type QueryInfoAndCounters struct {
	ID          string
	Namespace   string
	Operation   string
	Query       string
	Fingerprint string
	FirstSeen   time.Time
	LastSeen    time.Time
	TableScan   bool

	Count          int
	BlockedTime    Times
	LockTime       Times
	NReturned      []float64
	QueryTime      []float64 // in milliseconds
	ResponseLength []float64

	PlanSummary   string
	CollScanCount int

	DocsExamined []float64
	KeysExamined []float64
	QueryHash    string
	AppName      string
	Client       string
	User         string
	Comments     string

	LocksGlobalAcquireCountReadSharedCount       int
	LocksGlobalAcquireCountReadShared            int
	LocksGlobalAcquireCountWriteSharedCount      int
	LocksGlobalAcquireCountWriteShared           int
	LocksDatabaseAcquireCountReadSharedCount     int
	LocksDatabaseAcquireCountReadShared          int
	LocksDatabaseAcquireWaitCountReadSharedCount int
	LocksDatabaseAcquireWaitCountReadShared      int
	LocksDatabaseTimeAcquiringMicrosReadShared   []float64 // in microseconds
	LocksCollectionAcquireCountReadSharedCount   int
	LocksCollectionAcquireCountReadShared        int

	StorageBytesRead         []float64
	StorageTimeReadingMicros []float64 // in microseconds
}

// times is an array of time.Time that implements the Sorter interface
type Times []time.Time

func (a Times) Len() int           { return len(a) }
func (a Times) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a Times) Less(i, j int) bool { return a[i].Before(a[j]) }

type GroupKeys []GroupKey

func (a GroupKeys) Len() int           { return len(a) }
func (a GroupKeys) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a GroupKeys) Less(i, j int) bool { return a[i].String() < a[j].String() }

type GroupKey struct {
	Operation   string
	Namespace   string
	Fingerprint string
}

func (g GroupKey) String() string {
	return g.Operation + g.Namespace + g.Fingerprint
}

type totalCounters struct {
	Count                                      int
	Returned                                   float64
	QueryTime                                  float64
	Bytes                                      float64
	DocsExamined                               float64
	KeysExamined                               float64
	LocksDatabaseTimeAcquiringMicrosReadShared float64
	StorageBytesRead                           float64
	StorageTimeReadingMicros                   float64
}

type QueryStats struct {
	ID          string
	Namespace   string
	Operation   string
	Query       string
	Fingerprint string
	FirstSeen   time.Time
	LastSeen    time.Time

	Count               int
	QPS                 float64
	Rank                int
	Ratio               float64
	QueryTime           Statistics
	ResponseLengthCount int
	ResponseLength      Statistics
	Returned            Statistics

	PlanSummary       string
	CollScanCount     int
	DocsExaminedCount int
	DocsExamined      Statistics
	KeysExaminedCount int
	KeysExamined      Statistics
	QueryHash         string
	AppName           string
	Client            string
	User              string
	Comments          string

	LocksGlobalAcquireCountReadSharedCount          int
	LocksGlobalAcquireCountReadShared               int
	LocksGlobalAcquireCountWriteSharedCount         int
	LocksGlobalAcquireCountWriteShared              int
	LocksDatabaseAcquireCountReadSharedCount        int
	LocksDatabaseAcquireCountReadShared             int
	LocksDatabaseAcquireWaitCountReadSharedCount    int
	LocksDatabaseAcquireWaitCountReadShared         int
	LocksDatabaseTimeAcquiringMicrosReadSharedCount int
	LocksDatabaseTimeAcquiringMicrosReadShared      Statistics // in microseconds
	LocksCollectionAcquireCountReadSharedCount      int
	LocksCollectionAcquireCountReadShared           int

	StorageBytesReadCount         int
	StorageBytesRead              Statistics
	StorageTimeReadingMicrosCount int
	StorageTimeReadingMicros      Statistics // in microseconds
}

type Statistics struct {
	Pct    float64
	Total  float64
	Min    float64
	Max    float64
	Avg    float64
	Pct95  float64
	Pct99  float64
	StdDev float64
	Median float64
}

func countersToStats(query QueryInfoAndCounters, uptime int64, tc totalCounters) QueryStats {
	queryStats := QueryStats{
		Count:                                    query.Count,
		ID:                                       query.ID,
		Operation:                                query.Operation,
		Query:                                    query.Query,
		Fingerprint:                              query.Fingerprint,
		Returned:                                 calcStats(query.NReturned),
		QueryTime:                                calcStats(query.QueryTime),
		FirstSeen:                                query.FirstSeen,
		LastSeen:                                 query.LastSeen,
		Namespace:                                query.Namespace,
		QPS:                                      float64(query.Count) / float64(uptime),
		PlanSummary:                              query.PlanSummary,
		CollScanCount:                            query.CollScanCount,
		ResponseLengthCount:                      len(query.ResponseLength),
		ResponseLength:                           calcStats(query.ResponseLength),
		DocsExaminedCount:                        len(query.DocsExamined),
		DocsExamined:                             calcStats(query.DocsExamined),
		KeysExaminedCount:                        len(query.KeysExamined),
		KeysExamined:                             calcStats(query.KeysExamined),
		QueryHash:                                query.QueryHash,
		AppName:                                  query.AppName,
		Client:                                   query.Client,
		User:                                     query.User,
		Comments:                                 query.Comments,
		LocksGlobalAcquireCountReadSharedCount:   query.LocksGlobalAcquireCountReadSharedCount,
		LocksGlobalAcquireCountReadShared:        query.LocksGlobalAcquireCountReadShared,
		LocksGlobalAcquireCountWriteSharedCount:  query.LocksGlobalAcquireCountWriteSharedCount,
		LocksGlobalAcquireCountWriteShared:       query.LocksGlobalAcquireCountWriteShared,
		LocksDatabaseAcquireCountReadSharedCount: query.LocksDatabaseAcquireCountReadSharedCount,
		LocksDatabaseAcquireCountReadShared:      query.LocksDatabaseAcquireCountReadShared,
		LocksDatabaseAcquireWaitCountReadSharedCount:    query.LocksDatabaseAcquireWaitCountReadSharedCount,
		LocksDatabaseAcquireWaitCountReadShared:         query.LocksDatabaseAcquireWaitCountReadShared,
		LocksDatabaseTimeAcquiringMicrosReadSharedCount: len(query.LocksDatabaseTimeAcquiringMicrosReadShared),
		LocksDatabaseTimeAcquiringMicrosReadShared:      calcStats(query.LocksDatabaseTimeAcquiringMicrosReadShared),
		LocksCollectionAcquireCountReadSharedCount:      query.LocksCollectionAcquireCountReadSharedCount,
		LocksCollectionAcquireCountReadShared:           query.LocksCollectionAcquireCountReadShared,
		StorageBytesReadCount:                           len(query.StorageBytesRead),
		StorageBytesRead:                                calcStats(query.StorageBytesRead),
		StorageTimeReadingMicrosCount:                   len(query.StorageTimeReadingMicros),
		StorageTimeReadingMicros:                        calcStats(query.StorageTimeReadingMicros),
	}
	if tc.Returned > 0 {
		queryStats.Returned.Pct = queryStats.Returned.Total * 100 / tc.Returned
	}
	if tc.QueryTime > 0 {
		queryStats.QueryTime.Pct = queryStats.QueryTime.Total * 100 / tc.QueryTime
	}
	if tc.Bytes > 0 {
		queryStats.ResponseLength.Pct = queryStats.ResponseLength.Total * 100 / tc.Bytes
	}
	if queryStats.Returned.Total > 0 {
		queryStats.Ratio = queryStats.DocsExamined.Total / queryStats.Returned.Total
	}
	if tc.DocsExamined > 0 {
		queryStats.DocsExamined.Pct = queryStats.DocsExamined.Total * 100 / tc.DocsExamined
	}
	if tc.KeysExamined > 0 {
		queryStats.KeysExamined.Pct = queryStats.KeysExamined.Total * 100 / tc.KeysExamined
	}
	if tc.LocksDatabaseTimeAcquiringMicrosReadShared > 0 {
		queryStats.LocksDatabaseTimeAcquiringMicrosReadShared.Pct = queryStats.LocksDatabaseTimeAcquiringMicrosReadShared.Total * 100 / tc.LocksDatabaseTimeAcquiringMicrosReadShared
	}
	if tc.StorageBytesRead > 0 {
		queryStats.StorageBytesRead.Pct = queryStats.StorageBytesRead.Total * 100 / tc.StorageBytesRead
	}
	if tc.StorageTimeReadingMicros > 0 {
		queryStats.StorageTimeReadingMicros.Pct = queryStats.StorageTimeReadingMicros.Total * 100 / tc.StorageTimeReadingMicros
	}

	return queryStats
}

func aggregateCounters(queries []QueryInfoAndCounters) QueryInfoAndCounters {
	qt := QueryInfoAndCounters{}
	for _, query := range queries {
		qt.Count += query.Count
		qt.NReturned = append(qt.NReturned, query.NReturned...)
		qt.QueryTime = append(qt.QueryTime, query.QueryTime...)
		qt.ResponseLength = append(qt.ResponseLength, query.ResponseLength...)
		qt.DocsExamined = append(qt.DocsExamined, query.DocsExamined...)
		qt.KeysExamined = append(qt.KeysExamined, query.KeysExamined...)
		qt.LocksDatabaseTimeAcquiringMicrosReadShared = append(qt.LocksDatabaseTimeAcquiringMicrosReadShared, query.LocksDatabaseTimeAcquiringMicrosReadShared...)
		qt.StorageBytesRead = append(qt.StorageBytesRead, query.StorageBytesRead...)
		qt.StorageTimeReadingMicros = append(qt.StorageTimeReadingMicros, query.StorageTimeReadingMicros...)
	}
	return qt
}

func calcTotalCounters(queries []QueryInfoAndCounters) totalCounters {
	tc := totalCounters{}

	for _, query := range queries {
		tc.Count += query.Count

		returned, _ := stats.Sum(query.NReturned)
		tc.Returned += returned

		queryTime, _ := stats.Sum(query.QueryTime)
		tc.QueryTime += queryTime

		bytes, _ := stats.Sum(query.ResponseLength)
		tc.Bytes += bytes

		docsExamined, _ := stats.Sum(query.DocsExamined)
		tc.DocsExamined += docsExamined

		keysExamined, _ := stats.Sum(query.KeysExamined)
		tc.KeysExamined += keysExamined

		locksDatabaseTimeAcquiringMicrosReadShared, _ := stats.Sum(query.LocksDatabaseTimeAcquiringMicrosReadShared)
		tc.LocksDatabaseTimeAcquiringMicrosReadShared += locksDatabaseTimeAcquiringMicrosReadShared

		storageBytesRead, _ := stats.Sum(query.StorageBytesRead)
		tc.StorageBytesRead += storageBytesRead

		storageTimeReadingMicros, _ := stats.Sum(query.StorageTimeReadingMicros)
		tc.StorageTimeReadingMicros += storageTimeReadingMicros
	}
	return tc
}

func calcStats(samples []float64) Statistics {
	if len(samples) == 0 {
		return Statistics{}
	}

	var s Statistics
	s.Total, _ = stats.Sum(samples)
	s.Min, _ = stats.Min(samples)
	s.Max, _ = stats.Max(samples)
	s.Avg, _ = stats.Mean(samples)
	s.Pct95, _ = stats.PercentileNearestRank(samples, 95)
	s.Pct99, _ = stats.PercentileNearestRank(samples, 99)
	s.StdDev, _ = stats.StandardDeviation(samples)
	s.Median, _ = stats.Median(samples)
	return s
}
