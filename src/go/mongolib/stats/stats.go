package stats

import (
	"crypto/md5"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/montanaflynn/stats"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"gopkg.in/mgo.v2/bson"
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
		queryBson, err := bson.MarshalJSON(query)
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
		}
		s.setQueryInfoAndCounters(key, qiac)
	}
	qiac.Count++
	// docsExamined is renamed from nscannedObjects in 3.2.0.
	// https://docs.mongodb.com/manual/reference/database-profiler/#system.profile.docsExamined
	if doc.NscannedObjects > 0 {
		qiac.NScanned = append(qiac.NScanned, float64(doc.NscannedObjects))
	} else {
		qiac.NScanned = append(qiac.NScanned, float64(doc.DocsExamined))
	}
	qiac.NReturned = append(qiac.NReturned, float64(doc.Nreturned))
	qiac.QueryTime = append(qiac.QueryTime, float64(doc.Millis))
	qiac.ResponseLength = append(qiac.ResponseLength, float64(doc.ResponseLength))
	if qiac.FirstSeen.IsZero() || qiac.FirstSeen.After(doc.Ts) {
		qiac.FirstSeen = doc.Ts
	}
	if qiac.LastSeen.IsZero() || qiac.LastSeen.Before(doc.Ts) {
		qiac.LastSeen = doc.Ts
	}

	return nil
}

// Queries returns all collected statistics
func (s *Stats) Queries() Queries {
	s.RLock()
	defer s.RUnlock()

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
	NScanned       []float64
	QueryTime      []float64 // in milliseconds
	ResponseLength []float64
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
	Count     int
	Scanned   float64
	Returned  float64
	QueryTime float64
	Bytes     float64
}

type QueryStats struct {
	ID          string
	Namespace   string
	Operation   string
	Query       string
	Fingerprint string
	FirstSeen   time.Time
	LastSeen    time.Time

	Count          int
	QPS            float64
	Rank           int
	Ratio          float64
	QueryTime      Statistics
	ResponseLength Statistics
	Returned       Statistics
	Scanned        Statistics
}

type Statistics struct {
	Pct    float64
	Total  float64
	Min    float64
	Max    float64
	Avg    float64
	Pct95  float64
	StdDev float64
	Median float64
}

func countersToStats(query QueryInfoAndCounters, uptime int64, tc totalCounters) QueryStats {
	queryStats := QueryStats{
		Count:          query.Count,
		ID:             query.ID,
		Operation:      query.Operation,
		Query:          query.Query,
		Fingerprint:    query.Fingerprint,
		Scanned:        calcStats(query.NScanned),
		Returned:       calcStats(query.NReturned),
		QueryTime:      calcStats(query.QueryTime),
		ResponseLength: calcStats(query.ResponseLength),
		FirstSeen:      query.FirstSeen,
		LastSeen:       query.LastSeen,
		Namespace:      query.Namespace,
		QPS:            float64(query.Count) / float64(uptime),
	}
	if tc.Scanned > 0 {
		queryStats.Scanned.Pct = queryStats.Scanned.Total * 100 / tc.Scanned
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
		queryStats.Ratio = queryStats.Scanned.Total / queryStats.Returned.Total
	}

	return queryStats
}

func aggregateCounters(queries []QueryInfoAndCounters) QueryInfoAndCounters {
	qt := QueryInfoAndCounters{}
	for _, query := range queries {
		qt.Count += query.Count
		qt.NScanned = append(qt.NScanned, query.NScanned...)
		qt.NReturned = append(qt.NReturned, query.NReturned...)
		qt.QueryTime = append(qt.QueryTime, query.QueryTime...)
		qt.ResponseLength = append(qt.ResponseLength, query.ResponseLength...)
	}
	return qt
}

func calcTotalCounters(queries []QueryInfoAndCounters) totalCounters {
	tc := totalCounters{}

	for _, query := range queries {
		tc.Count += query.Count

		scanned, _ := stats.Sum(query.NScanned)
		tc.Scanned += scanned

		returned, _ := stats.Sum(query.NReturned)
		tc.Returned += returned

		queryTime, _ := stats.Sum(query.QueryTime)
		tc.QueryTime += queryTime

		bytes, _ := stats.Sum(query.ResponseLength)
		tc.Bytes += bytes
	}
	return tc
}

func calcStats(samples []float64) Statistics {
	var s Statistics
	s.Total, _ = stats.Sum(samples)
	s.Min, _ = stats.Min(samples)
	s.Max, _ = stats.Max(samples)
	s.Avg, _ = stats.Mean(samples)
	s.Pct95, _ = stats.PercentileNearestRank(samples, 95)
	s.StdDev, _ = stats.StandardDeviation(samples)
	s.Median, _ = stats.Median(samples)
	return s
}
