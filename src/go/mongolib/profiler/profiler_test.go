package profiler

import (
	"fmt"
	"log"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/golang/mock/gomock"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
	"github.com/percona/pmgo/pmgomock"
)

const (
	samples = "/src/go/tests/"
)

type testVars struct {
	RootPath string
}

var vars testVars

func parseDate(dateStr string) time.Time {
	date, _ := time.Parse(time.RFC3339Nano, dateStr)
	return date
}

func TestMain(m *testing.M) {
	var err error
	if vars.RootPath, err = tutil.RootPath(); err != nil {
		log.Printf("cannot get root path: %s", err.Error())
		os.Exit(1)
	}
	os.Exit(m.Run())
}

func TestRegularIterator(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	iter := pmgomock.NewMockIterManager(ctrl)
	gomock.InOrder(
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[0]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[1]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).Return(false),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Close(),
	)
	filters := []filter.Filter{}
	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	prof := NewProfiler(iter, filters, nil, fp)

	firstSeen, _ := time.Parse(time.RFC3339Nano, "2017-04-01T23:01:19.914+00:00")
	lastSeen, _ := time.Parse(time.RFC3339Nano, "2017-04-01T23:01:20.214+00:00")
	want := []QueryInfoAndCounters{
		QueryInfoAndCounters{
			ID:        "c6466139b21c392acd0699e863b50d81",
			Namespace: "samples.col1",
			Operation: "query",
			Query: map[string]interface{}{
				"find":         "col1",
				"shardVersion": []interface{}{float64(0), "000000000000000000000000"},
			},
			Fingerprint:    "find",
			FirstSeen:      firstSeen,
			LastSeen:       lastSeen,
			TableScan:      false,
			Count:          2,
			BlockedTime:    Times(nil),
			LockTime:       Times(nil),
			NReturned:      []float64{50, 75},
			NScanned:       []float64{100, 75},
			QueryTime:      []float64{0, 1},
			ResponseLength: []float64{1.06123e+06, 1.06123e+06},
		},
	}
	prof.Start()
	select {
	case queries := <-prof.QueriesChan():
		if !reflect.DeepEqual(queries, want) {
			t.Errorf("invalid queries. \nGot: %#v,\nWant: %#v\n", queries, want)
		}
	case <-time.After(2 * time.Second):
		t.Error("Didn't get any query")
	}
}

func TestIteratorTimeout(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	iter := pmgomock.NewMockIterManager(ctrl)
	gomock.InOrder(
		iter.EXPECT().Next(gomock.Any()).Return(true),
		iter.EXPECT().Timeout().Return(true),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[1]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).Return(false),
		iter.EXPECT().Timeout().Return(false),
		// When there are no more docs, iterator will close
		iter.EXPECT().Close(),
	)
	filters := []filter.Filter{}

	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	prof := NewProfiler(iter, filters, nil, fp)

	firstSeen, _ := time.Parse(time.RFC3339Nano, "2017-04-01T23:01:19.914+00:00")
	lastSeen, _ := time.Parse(time.RFC3339Nano, "2017-04-01T23:01:19.914+00:00")
	want := []QueryInfoAndCounters{
		QueryInfoAndCounters{
			ID:        "c6466139b21c392acd0699e863b50d81",
			Namespace: "samples.col1",
			Operation: "query",
			Query: map[string]interface{}{
				"find":         "col1",
				"shardVersion": []interface{}{float64(0), "000000000000000000000000"},
			},
			Fingerprint:    "find",
			FirstSeen:      firstSeen,
			LastSeen:       lastSeen,
			TableScan:      false,
			Count:          1,
			BlockedTime:    Times(nil),
			LockTime:       Times(nil),
			NReturned:      []float64{75},
			NScanned:       []float64{75},
			QueryTime:      []float64{1},
			ResponseLength: []float64{1.06123e+06},
		},
	}

	prof.Start()
	gotTimeout := false

	// Get a timeout
	select {
	case <-prof.TimeoutsChan():
		gotTimeout = true
	case <-prof.QueriesChan():
		t.Error("Got queries before timeout")
	case <-time.After(2 * time.Second):
		t.Error("Timeout checking timeout")
	}
	if !gotTimeout {
		t.Error("Didn't get a timeout")
	}

	// After the first document returned a timeout, we should still receive the second document
	select {
	case queries := <-prof.QueriesChan():
		if !reflect.DeepEqual(queries, want) {
			t.Errorf("invalid queries. \nGot: %#v,\nWant: %#v\n", queries, want)
		}
	case <-time.After(2 * time.Second):
		t.Error("Didn't get any query after 2 seconds")
	}

	prof.Stop()
}

func TestTailIterator(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	sleep := func(param interface{}) {
		time.Sleep(1500 * time.Millisecond)
	}

	iter := pmgomock.NewMockIterManager(ctrl)
	gomock.InOrder(
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[0]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		// A Tail iterator will wait if the are no available docs.
		// Do a 1500 ms sleep before returning the second doc to simulate a tail wait
		// and to let the ticker tick
		iter.EXPECT().Next(gomock.Any()).Do(sleep).SetArg(0, docs[1]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).Return(false),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Close(),
	)

	filters := []filter.Filter{}
	ticker := time.NewTicker(time.Second)
	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	prof := NewProfiler(iter, filters, ticker.C, fp)

	want := []QueryInfoAndCounters{
		QueryInfoAndCounters{
			ID:        "c6466139b21c392acd0699e863b50d81",
			Namespace: "samples.col1",
			Operation: "query",
			Query: map[string]interface{}{
				"find":         "col1",
				"shardVersion": []interface{}{float64(0), "000000000000000000000000"},
			},
			Fingerprint:    "find",
			FirstSeen:      parseDate("2017-04-01T23:01:20.214+00:00"),
			LastSeen:       parseDate("2017-04-01T23:01:20.214+00:00"),
			TableScan:      false,
			Count:          1,
			BlockedTime:    Times(nil),
			LockTime:       Times(nil),
			NReturned:      []float64{50},
			NScanned:       []float64{100},
			QueryTime:      []float64{0},
			ResponseLength: []float64{1.06123e+06},
		},
		QueryInfoAndCounters{
			ID:        "c6466139b21c392acd0699e863b50d81",
			Namespace: "samples.col1",
			Operation: "query",
			Query: map[string]interface{}{
				"find":         "col1",
				"shardVersion": []interface{}{float64(0), "000000000000000000000000"},
			},
			Fingerprint:    "find",
			FirstSeen:      parseDate("2017-04-01T23:01:19.914+00:00"),
			LastSeen:       parseDate("2017-04-01T23:01:19.914+00:00"),
			TableScan:      false,
			Count:          1,
			BlockedTime:    Times(nil),
			LockTime:       Times(nil),
			NReturned:      []float64{75},
			NScanned:       []float64{75},
			QueryTime:      []float64{1},
			ResponseLength: []float64{1.06123e+06},
		},
	}
	prof.Start()
	index := 0
	// Since the mocked iterator has a Sleep(1500 ms) between Next methods calls,
	// we are going to have two ticker ticks and on every tick it will return one document.
	for index < 2 {
		select {
		case queries := <-prof.QueriesChan():
			if !reflect.DeepEqual(queries, []QueryInfoAndCounters{want[index]}) {
				t.Errorf("invalid queries. \nGot: %#v,\nWant: %#v\n", queries, want)
			}
			index++
		}
	}
}

func TestCalcStats(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs_stats.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	want := []QueryStats{}
	err = tutil.LoadJson(vars.RootPath+samples+"profiler_docs_stats.want.json", &want)
	if err != nil {
		t.Fatalf("cannot load expected results: %s", err.Error())
	}

	iter := pmgomock.NewMockIterManager(ctrl)
	gomock.InOrder(
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[0]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[1]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[2]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).Return(false),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Close(),
	)

	filters := []filter.Filter{}
	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	prof := NewProfiler(iter, filters, nil, fp)

	prof.Start()
	select {
	case queries := <-prof.QueriesChan():
		stats := CalcQueriesStats(queries, 1)
		if os.Getenv("UPDATE_SAMPLES") != "" {
			tutil.WriteJson(vars.RootPath+samples+"profiler_docs_stats.want.json", stats)
		}
		if !reflect.DeepEqual(stats, want) {
			t.Errorf("Invalid stats.\nGot:%#v\nWant: %#v\n", stats, want)
		}
	case <-time.After(2 * time.Second):
		t.Error("Didn't get any query")
	}
}

func TestCalcTotalStats(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs_stats.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	want := QueryStats{}
	err = tutil.LoadJson(vars.RootPath+samples+"profiler_docs_total_stats.want.json", &want)
	if err != nil && !tutil.ShouldUpdateSamples() {
		t.Fatalf("cannot load expected results: %s", err.Error())
	}

	iter := pmgomock.NewMockIterManager(ctrl)
	gomock.InOrder(
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[0]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[1]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[2]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).Return(false),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Close(),
	)

	filters := []filter.Filter{}
	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	prof := NewProfiler(iter, filters, nil, fp)

	prof.Start()
	select {
	case queries := <-prof.QueriesChan():
		stats := CalcTotalQueriesStats(queries, 1)
		if os.Getenv("UPDATE_SAMPLES") != "" {
			fmt.Println("Updating samples: " + vars.RootPath + samples + "profiler_docs_total_stats.want.json")
			err := tutil.WriteJson(vars.RootPath+samples+"profiler_docs_total_stats.want.json", stats)
			if err != nil {
				fmt.Printf("cannot update samples: %s", err.Error())
			}
		}
		if !reflect.DeepEqual(stats, want) {
			t.Errorf("Invalid stats.\nGot:%#v\nWant: %#v\n", stats, want)
		}
	case <-time.After(2 * time.Second):
		t.Error("Didn't get any query")
	}
}

func TestCalcTotalCounters(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs_stats.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	want := totalCounters{}
	err = tutil.LoadJson(vars.RootPath+samples+"profiler_docs_total_counters.want.json", &want)
	if err != nil && !tutil.ShouldUpdateSamples() {
		t.Fatalf("cannot load expected results: %s", err.Error())
	}

	iter := pmgomock.NewMockIterManager(ctrl)
	gomock.InOrder(
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[0]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[1]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).SetArg(0, docs[2]).Return(true),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Next(gomock.Any()).Return(false),
		iter.EXPECT().Timeout().Return(false),
		iter.EXPECT().Close(),
	)

	filters := []filter.Filter{}
	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	prof := NewProfiler(iter, filters, nil, fp)

	prof.Start()
	select {
	case queries := <-prof.QueriesChan():
		counters := calcTotalCounters(queries)
		if tutil.ShouldUpdateSamples() {
			fmt.Println("Updating samples: " + vars.RootPath + samples + "profiler_docs_total_counters.want.json")
			err := tutil.WriteJson(vars.RootPath+samples+"profiler_docs_total_counters.want.json", counters)
			if err != nil {
				fmt.Printf("cannot update samples: %s", err.Error())
			}
		}
		if !reflect.DeepEqual(counters, want) {
			t.Errorf("Invalid counters.\nGot:%#v\nWant: %#v\n", counters, want)
		}
	case <-time.After(2 * time.Second):
		t.Error("Didn't get any query")
	}
}

func TestProcessDoc(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs_stats.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	iter := pmgomock.NewMockIterManager(ctrl)
	filters := []filter.Filter{}
	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	prof := NewProfiler(iter, filters, nil, fp)

	var stats = make(map[StatsGroupKey]*QueryInfoAndCounters)

	err = prof.ProcessDoc(docs[1], stats)
	if err != nil {
		t.Errorf("Error processing doc: %s\n", err.Error())
	}
	statsKey := StatsGroupKey{Operation: "query", Fingerprint: "s2", Namespace: "samples.col1"}
	statsVal := &QueryInfoAndCounters{
		ID:             "84e09ef6a3dc35f472df05fa98eee7d3",
		Namespace:      "samples.col1",
		Operation:      "query",
		Query:          map[string]interface{}{"s2": map[string]interface{}{"$gte": "41991", "$lt": "33754"}},
		Fingerprint:    "s2",
		FirstSeen:      parseDate("2017-04-10T13:15:53.532-03:00"),
		LastSeen:       parseDate("2017-04-10T13:15:53.532-03:00"),
		TableScan:      false,
		Count:          1,
		BlockedTime:    nil,
		LockTime:       nil,
		NReturned:      []float64{0},
		NScanned:       []float64{10000},
		QueryTime:      []float64{7},
		ResponseLength: []float64{215},
	}

	want := map[StatsGroupKey]*QueryInfoAndCounters{statsKey: statsVal}

	if !reflect.DeepEqual(stats, want) {
		t.Errorf("Error in ProcessDoc.\nGot:%#v\nWant: %#v\n", stats, want)
	}
}

func TestTimesLen(t *testing.T) {
	tests := []struct {
		name string
		a    times
		want int
	}{
		{
			name: "Times.Len",
			a:    []time.Time{time.Now()},
			want: 1,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.a.Len(); got != tt.want {
				t.Errorf("times.Len() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestTimesSwap(t *testing.T) {
	type args struct {
		i int
		j int
	}
	t1 := time.Now()
	t2 := t1.Add(1 * time.Minute)
	tests := []struct {
		name string
		a    times
		args args
	}{
		{
			name: "Times.Swap",
			a:    times{t1, t2},
			args: args{i: 0, j: 1},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.a.Swap(tt.args.i, tt.args.j)
			if tt.a[0] != t2 || tt.a[1] != t1 {
				t.Errorf("%s has (%v, %v) want (%v, %v)", tt.name, tt.a[0], tt.a[1], t2, t1)
			}
		})
	}
}

func TestTimesLess(t *testing.T) {
	type args struct {
		i int
		j int
	}
	t1 := time.Now()
	t2 := t1.Add(1 * time.Minute)
	tests := []struct {
		name string
		a    times
		args args
		want bool
	}{
		{
			name: "Times.Swap",
			a:    times{t1, t2},
			args: args{i: 0, j: 1},
			want: true,
		},
		{
			name: "Times.Swap",
			a:    times{t2, t1},
			args: args{i: 0, j: 1},
			want: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.a.Less(tt.args.i, tt.args.j); got != tt.want {
				t.Errorf("times.Less() = %v, want %v", got, tt.want)
			}
		})
	}
}
