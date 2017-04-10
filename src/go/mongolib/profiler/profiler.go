package profiler

import (
	"crypto/md5"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/montanaflynn/stats"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
	"github.com/percona/pmgo"
)

var (
	// MaxDepthLevel Max recursion level for the fingerprinter
	MaxDepthLevel = 10
	// DocsBufferSize is the buffer size to store documents from the MongoDB profiler
	DocsBufferSize = 100
	// ErrCannotGetQuery is the error returned if we cannot find a query into the profiler document
	ErrCannotGetQuery = errors.New("cannot get query field from the profile document (it is not a map)")
)

// Times is an array of time.Time that implements the Sorter interface
type Times []time.Time

func (a Times) Len() int           { return len(a) }
func (a Times) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a Times) Less(i, j int) bool { return a[i].Before(a[j]) }

type StatsGroupKey struct {
	Operation   string
	Fingerprint string
	Namespace   string
}

type totalCounters struct {
	Count     int
	Scanned   float64
	Returned  float64
	QueryTime float64
	Bytes     float64
}

type Profiler interface {
	GetLastError() error
	QueriesChan() chan []QueryInfoAndCounters
	TimeoutsChan() <-chan time.Time
	Start()
	Stop()
}

type Profile struct {
	filters                []filter.Filter
	iterator               pmgo.IterManager
	ticker                 <-chan time.Time
	queriesChan            chan []QueryInfoAndCounters
	stopChan               chan bool
	docsChan               chan proto.SystemProfile
	timeoutsChan           chan time.Time
	queriesInfoAndCounters map[StatsGroupKey]*QueryInfoAndCounters
	keyFilters             []string
	fingerprinter          fingerprinter.Fingerprinter
	running                bool
	lastError              error
	stopWaitGroup          sync.WaitGroup
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

type QueryInfoAndCounters struct {
	ID          string
	Namespace   string
	Operation   string
	Query       map[string]interface{}
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

func NewProfiler(iterator pmgo.IterManager, filters []filter.Filter, ticker <-chan time.Time, fp fingerprinter.Fingerprinter) Profiler {
	return &Profile{
		filters:                filters,
		fingerprinter:          fp,
		iterator:               iterator,
		ticker:                 ticker,
		queriesChan:            make(chan []QueryInfoAndCounters),
		docsChan:               make(chan proto.SystemProfile, DocsBufferSize),
		timeoutsChan:           nil,
		queriesInfoAndCounters: make(map[StatsGroupKey]*QueryInfoAndCounters),
		keyFilters:             []string{"^shardVersion$", "^\\$"},
	}
}

func (p *Profile) GetLastError() error {
	return p.lastError
}

func (p *Profile) QueriesChan() chan []QueryInfoAndCounters {
	return p.queriesChan
}

func (p *Profile) Start() {
	if !p.running {
		p.running = true
		p.stopChan = make(chan bool)
		go p.getData()
	}
}

func (p *Profile) Stop() {
	if p.running {
		select {
		case p.stopChan <- true:
		default:
		}
		close(p.timeoutsChan)
		// Wait for getData to receive the stop signal
		p.stopWaitGroup.Wait()
		p.iterator.Close()
	}
}

func (p *Profile) TimeoutsChan() <-chan time.Time {
	if p.timeoutsChan == nil {
		p.timeoutsChan = make(chan time.Time)
	}
	return p.timeoutsChan
}

func (p *Profile) getData() {
	go p.getDocs()
	p.stopWaitGroup.Add(1)

MAIN_GETDATA_LOOP:
	for {
		select {
		case <-p.ticker:
			p.queriesChan <- mapToArray(p.queriesInfoAndCounters)
			p.queriesInfoAndCounters = make(map[StatsGroupKey]*QueryInfoAndCounters) // Reset stats
		case <-p.stopChan:
			p.iterator.Close()
			break MAIN_GETDATA_LOOP
		}
	}
	p.stopWaitGroup.Done()
}

func (p *Profile) getDocs() {
	var doc proto.SystemProfile

	for p.iterator.Next(&doc) || p.iterator.Timeout() {
		if p.iterator.Timeout() {
			if p.timeoutsChan != nil {
				p.timeoutsChan <- time.Now().UTC()
			}
			continue
		}
		valid := true
		for _, filter := range p.filters {
			if filter(doc) == false {
				valid = false
				break
			}
		}
		if !valid {
			continue
		}
		if len(doc.Query) > 0 {
			p.ProcessDoc(doc, p.queriesInfoAndCounters)
		}
	}
	p.queriesChan <- mapToArray(p.queriesInfoAndCounters)
	select {
	case p.stopChan <- true:
	default:
	}
}

func (p *Profile) ProcessDoc(doc proto.SystemProfile, stats map[StatsGroupKey]*QueryInfoAndCounters) error {

	fp, err := p.fingerprinter.Fingerprint(doc.Query)
	if err != nil {
		return fmt.Errorf("cannot get fingerprint: %s", err.Error())
	}
	var s *QueryInfoAndCounters
	var ok bool
	key := StatsGroupKey{
		Operation:   doc.Op,
		Fingerprint: fp,
		Namespace:   doc.Ns,
	}
	if s, ok = p.queriesInfoAndCounters[key]; !ok {
		realQuery, _ := util.GetQueryField(doc.Query)
		s = &QueryInfoAndCounters{
			ID:          fmt.Sprintf("%x", md5.Sum([]byte(fmt.Sprintf("%s", key)))),
			Operation:   doc.Op,
			Fingerprint: fp,
			Namespace:   doc.Ns,
			TableScan:   false,
			Query:       realQuery,
		}
		p.queriesInfoAndCounters[key] = s
	}
	s.Count++
	s.NScanned = append(s.NScanned, float64(doc.DocsExamined))
	s.NReturned = append(s.NReturned, float64(doc.Nreturned))
	s.QueryTime = append(s.QueryTime, float64(doc.Millis))
	s.ResponseLength = append(s.ResponseLength, float64(doc.ResponseLength))
	var zeroTime time.Time
	if s.FirstSeen == zeroTime || s.FirstSeen.After(doc.Ts) {
		s.FirstSeen = doc.Ts
	}
	if s.LastSeen == zeroTime || s.LastSeen.Before(doc.Ts) {
		s.LastSeen = doc.Ts
	}

	return nil

}

func CalcQueriesStats(queries []QueryInfoAndCounters, uptime int64) []QueryStats {
	stats := []QueryStats{}
	tc := calcTotalCounters(queries)

	for _, query := range queries {
		queryStats := CountersToStats(query, uptime, tc)
		stats = append(stats, queryStats)
	}

	return stats
}

func CalcTotalQueriesStats(queries []QueryInfoAndCounters, uptime int64) QueryStats {
	tc := calcTotalCounters(queries)

	totalQueryInfoAndCounters := aggregateCounters(queries)
	totalStats := CountersToStats(totalQueryInfoAndCounters, uptime, tc)

	return totalStats
}

func CountersToStats(query QueryInfoAndCounters, uptime int64, tc totalCounters) QueryStats {
	buf, _ := json.Marshal(query.Query)
	queryStats := QueryStats{
		Count:          query.Count,
		ID:             query.ID,
		Operation:      query.Operation,
		Query:          string(buf),
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
		queryStats.ResponseLength.Pct = queryStats.ResponseLength.Total / tc.Bytes
	}
	if queryStats.Returned.Total > 0 {
		queryStats.Ratio = queryStats.Scanned.Total / queryStats.Returned.Total
	}

	return queryStats
}

func aggregateCounters(queries []QueryInfoAndCounters) QueryInfoAndCounters {
	qt := QueryInfoAndCounters{}
	for _, query := range queries {
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

func mapToArray(stats map[StatsGroupKey]*QueryInfoAndCounters) []QueryInfoAndCounters {
	sa := []QueryInfoAndCounters{}
	for _, s := range stats {
		sa = append(sa, *s)
	}
	return sa
}
