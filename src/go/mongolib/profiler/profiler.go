package profiler

import (
	"sync"
	"time"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
	"github.com/percona/pmgo"
)

var (
	// DocsBufferSize is the buffer size to store documents from the MongoDB profiler
	DocsBufferSize = 100
)

type Profiler interface {
	GetLastError() error
	QueriesChan() chan stats.Queries
	TimeoutsChan() <-chan time.Time
	Start()
	Stop()
}

type Profile struct {
	// dependencies
	iterator pmgo.IterManager
	filters  []filter.Filter
	ticker   <-chan time.Time
	stats    Stats

	// internal
	queriesChan  chan stats.Queries
	stopChan     chan bool
	docsChan     chan proto.SystemProfile
	timeoutsChan chan time.Time
	// For the moment ProcessDoc is exportable to it could be called from the "outside"
	// For that reason, we need a mutex to make it thread safe. In the future this func
	// will be unexported
	countersMapLock sync.Mutex
	keyFilters      []string
	lock            sync.Mutex
	running         bool
	lastError       error
	stopWaitGroup   sync.WaitGroup
}

func NewProfiler(iterator pmgo.IterManager, filters []filter.Filter, ticker <-chan time.Time, stats Stats) Profiler {
	return &Profile{
		// dependencies
		iterator: iterator,
		filters:  filters,
		ticker:   ticker,
		stats:    stats,

		// internal
		docsChan:     make(chan proto.SystemProfile, DocsBufferSize),
		timeoutsChan: nil,
		keyFilters:   []string{"^shardVersion$", "^\\$"},
	}
}

func (p *Profile) GetLastError() error {
	return p.lastError
}

func (p *Profile) QueriesChan() chan stats.Queries {
	return p.queriesChan
}

func (p *Profile) Start() {
	p.lock.Lock()
	defer p.lock.Unlock()
	if !p.running {
		p.running = true
		p.queriesChan = make(chan stats.Queries)
		p.stopChan = make(chan bool)
		go p.getData()
	}
}

func (p *Profile) Stop() {
	p.lock.Lock()
	defer p.lock.Unlock()
	if p.running {
		select {
		case p.stopChan <- true:
		default:
		}
		// Wait for getData to receive the stop signal
		p.stopWaitGroup.Wait()
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
			p.queriesChan <- p.stats.Queries()
			p.stats.Reset()
		case <-p.stopChan:
			// Close the iterator to break the loop on getDocs
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
			p.stats.Add(doc)
		}
	}
	p.queriesChan <- p.stats.Queries()
	p.Stop()
}
