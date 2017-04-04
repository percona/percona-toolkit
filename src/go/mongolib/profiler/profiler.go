package profiler

import (
	"crypto/md5"
	"errors"
	"fmt"
	"time"

	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
	"github.com/prometheus/common/log"
)

var (
	MAX_DEPTH_LEVEL        = 10
	DOCS_BUFFER_SIZE       = 100
	CANNOT_GET_QUERY_ERROR = errors.New("cannot get query field from the profile document (it is not a map)")
)

type Times []time.Time

func (a Times) Len() int           { return len(a) }
func (a Times) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a Times) Less(i, j int) bool { return a[i].Before(a[j]) }

type StatsGroupKey struct {
	Operation   string
	Fingerprint string
	Namespace   string
}

type Stat struct {
	BlockedTime    Times
	Count          int
	Fingerprint    string
	FirstSeen      time.Time
	ID             string
	LastSeen       time.Time
	LockTime       Times
	NReturned      []float64
	NScanned       []float64
	Namespace      string
	Operation      string
	Query          map[string]interface{}
	QueryTime      []float64 // in milliseconds
	ResponseLength []float64
	TableScan      bool
}

type Iter interface {
	All(result interface{}) error
	Close() error
	Err() error
	For(result interface{}, f func() error) (err error)
	Next(result interface{}) bool
	Timeout() bool
}

type Profiler interface {
	GetLastError() error
	StatsChan() chan []Stat
	Start()
	Stop()
}

type Profile struct {
	filters       []filter.Filter
	iterator      Iter
	ticker        chan time.Time
	statsChan     chan []Stat
	stopChan      chan bool
	docsChan      chan proto.SystemProfile
	rawStats      map[StatsGroupKey]*Stat
	keyFilters    []string
	fingerprinter fingerprinter.Fingerprinter
	running       bool
	lastError     error
}

func NewProfiler(iterator Iter, filters []filter.Filter, ticker chan time.Time, fp fingerprinter.Fingerprinter) Profiler {
	return &Profile{
		filters:       filters,
		fingerprinter: fp,
		iterator:      iterator,
		ticker:        ticker,
		statsChan:     make(chan []Stat),
		docsChan:      make(chan proto.SystemProfile, DOCS_BUFFER_SIZE),
		rawStats:      make(map[StatsGroupKey]*Stat),
		keyFilters:    []string{"^shardVersion$", "^\\$"},
	}
}

func (p *Profile) GetLastError() error {
	return p.lastError
}

func (p *Profile) StatsChan() chan []Stat {
	return p.statsChan
}

func (p *Profile) Start() {
	if !p.running {
		p.running = true
		go p.getData()
	}
}

func (p *Profile) Stop() {
	if p.running {
		p.iterator.Close()
		close(p.stopChan)
	}
}

func (p *Profile) getData() {
	go p.getDocs()
MAIN_GETDATA_LOOP:
	for {
		select {
		case <-p.ticker:
			p.statsChan <- statsToArray(p.rawStats)
			p.rawStats = make(map[StatsGroupKey]*Stat) // Reset stats
		case <-p.stopChan:
			p.iterator.Close()
			break MAIN_GETDATA_LOOP
		}
	}
}

func (p *Profile) getDocs() {
	var doc proto.SystemProfile

	for p.iterator.Next(&doc) || p.iterator.Timeout() {
		if p.iterator.Timeout() {
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

			fp, err := p.fingerprinter.Fingerprint(doc.Query)
			if err != nil {
				log.Errorf("cannot get fingerprint: %s", err.Error())
				continue
			}
			var s *Stat
			var ok bool
			key := StatsGroupKey{
				Operation:   doc.Op,
				Fingerprint: fp,
				Namespace:   doc.Ns,
			}
			if s, ok = p.rawStats[key]; !ok {
				realQuery, _ := util.GetQueryField(doc.Query)
				s = &Stat{
					ID:          fmt.Sprintf("%x", md5.Sum([]byte(fmt.Sprintf("%s", key)))),
					Operation:   doc.Op,
					Fingerprint: fp,
					Namespace:   doc.Ns,
					TableScan:   false,
					Query:       realQuery,
				}
				p.rawStats[key] = s
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
		}
	}
	p.statsChan <- statsToArray(p.rawStats)
	p.running = false
	p.stopChan <- true
}

func statsToArray(stats map[StatsGroupKey]*Stat) []Stat {
	sa := []Stat{}
	for _, s := range stats {
		sa = append(sa, *s)
	}
	return sa
}
