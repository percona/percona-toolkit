package stats

import (
	"github.com/golang/mock/gomock"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"log"
	"os"
	"reflect"
	"testing"
	"time"
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

func TestTimesLen(t *testing.T) {
	tests := []struct {
		name string
		a    Times
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
		a    Times
		args args
	}{
		{
			name: "Times.Swap",
			a:    Times{t1, t2},
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
		a    Times
		args args
		want bool
	}{
		{
			name: "Times.Swap",
			a:    Times{t1, t2},
			args: args{i: 0, j: 1},
			want: true,
		},
		{
			name: "Times.Swap",
			a:    Times{t2, t1},
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

func TestStats(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	docs := []proto.SystemProfile{}
	err := tutil.LoadJson(vars.RootPath+samples+"profiler_docs_stats.json", &docs)
	if err != nil {
		t.Fatalf("cannot load samples: %s", err.Error())
	}

	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	s := New(fp)

	err = s.Add(docs[1])
	if err != nil {
		t.Errorf("Error processing doc: %s\n", err.Error())
	}
	statsVal := QueryInfoAndCounters{
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

	want := Queries{
		statsVal,
	}
	got := s.Queries()

	if !reflect.DeepEqual(got, want) {
		t.Errorf("Error \nGot:%#v\nWant: %#v\n", got, want)
	}
}
