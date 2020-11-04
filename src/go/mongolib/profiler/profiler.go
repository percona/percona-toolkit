package profiler

import (
	"context"
	"sync"
	"time"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
	"go.mongodb.org/mongo-driver/mongo"
)

// DocsBufferSize is the buffer size to store documents from the MongoDB profiler
var DocsBufferSize = 100

// Profiler interface
type Profiler interface {
	GetLastError() error
	QueriesChan() chan stats.Queries
	TimeoutsChan() <-chan time.Time
	FlushQueries()
	Start(context.Context)
	Stop()
}

// Profile has unexported variables for the profiler
type Profile struct {
	// dependencies
	cursor  *mongo.Cursor
	filters []filter.Filter
	ticker  <-chan time.Time
	stats   Stats

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

// NewProfiler returns a new instance of the profiler interface
func NewProfiler(cursor *mongo.Cursor, filters []filter.Filter, ticker <-chan time.Time, stats Stats) Profiler {
	return &Profile{
		cursor:  cursor,
		filters: filters,
		ticker:  ticker,
		stats:   stats,

		// internal
		docsChan:     make(chan proto.SystemProfile, DocsBufferSize),
		timeoutsChan: make(chan time.Time),
		keyFilters:   []string{"^shardVersion$", "^\\$"},
	}
}

// GetLastError return the latest error
func (p *Profile) GetLastError() error {
	return p.lastError
}

// QueriesChan returns the channels used to read the queries from the profiler
func (p *Profile) QueriesChan() chan stats.Queries {
	return p.queriesChan
}

// Start the profiler
func (p *Profile) Start(ctx context.Context) {
	p.lock.Lock()
	defer p.lock.Unlock()
	if !p.running {
		p.running = true
		p.queriesChan = make(chan stats.Queries)
		p.stopChan = make(chan bool)
		go p.getData(ctx)
	}
}

// Stop the profiler
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

// TimeoutsChan returns the channels to receive timeout signals
func (p *Profile) TimeoutsChan() <-chan time.Time {
	p.lock.Lock()
	defer p.lock.Unlock()
	return p.timeoutsChan
}

func (p *Profile) getData(ctx context.Context) {
	go p.getDocs(ctx)
	p.stopWaitGroup.Add(1)
	defer p.stopWaitGroup.Done()

	for {
		select {
		case <-p.ticker:
			p.FlushQueries()
		case <-p.stopChan:
			// Close the iterator to break the loop on getDocs
			p.lastError = p.cursor.Close(ctx)
			return
		}
	}
}

func (p *Profile) getDocs(ctx context.Context) {
	defer p.Stop()
	defer p.FlushQueries()

	var doc proto.SystemProfile

	for p.cursor.Next(ctx) {
		if err := p.cursor.Decode(&doc); err != nil {
			p.lastError = err
			return
		}
		valid := true
		for _, filter := range p.filters {
			if !filter(doc) {
				valid = false
				return
			}
		}
		if !valid {
			continue
		}
		p.lastError = p.stats.Add(doc)
	}
}

// FlushQueries clean all the queries from the queries chan
func (p *Profile) FlushQueries() {
	p.queriesChan <- p.stats.Queries()
	p.stats.Reset()
}
