package stats

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"reflect"
	"sort"
	"strings"
	"testing"
	"text/template"
	"time"

	"github.com/golang/mock/gomock"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
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
		ID:             "d7088d6b50551d1f2f5f34b006c0140d",
		Namespace:      "samples.col1",
		Operation:      "FIND",
		Query:          "{\"ns\":\"samples.col1\",\"op\":\"query\",\"query\":{\"find\":\"col1\",\"filter\":{\"s2\":{\"$gte\":\"41991\",\"$lt\":\"33754\"}},\"shardVersion\":[0,\"000000000000000000000000\"]}}\n",
		Fingerprint:    "FIND col1 s2",
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

func TestStatsSingle(t *testing.T) {
	t.Parallel()

	dirExpect := vars.RootPath + samples + "/expect/stats_single/"

	dir := vars.RootPath + samples + "/doc/out/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)

	for _, file := range files {
		f := file.Name()
		t.Run(f, func(t *testing.T) {
			t.Parallel()

			doc := proto.SystemProfile{}
			err = tutil.LoadBson(dir+f, &doc)
			if err != nil {
				t.Fatalf("cannot load sample %s: %s", dir+f, err)
			}
			s := New(fp)

			err = s.Add(doc)
			if err != nil {
				t.Errorf("Error processing doc: %s\n", err.Error())
			}
			got := s.Queries()
			expect := Queries{}
			if tutil.ShouldUpdateSamples() {
				err := tutil.WriteJson(dirExpect+f, got)
				if err != nil {
					fmt.Printf("cannot update samples: %s", err.Error())
				}
			}
			err = tutil.LoadJson(dirExpect+f, &expect)
			if err != nil {
				t.Fatalf("cannot load expected data %s: %s", dirExpect+f, err)
			}
			if !reflect.DeepEqual(got, expect) {
				t.Errorf("s.Queries() = %#v, want %#v", got, expect)
			}
		})
	}

}

func TestStatsAll(t *testing.T) {
	t.Parallel()

	f := vars.RootPath + samples + "/expect/stats_all/sum.json"

	dir := vars.RootPath + samples + "/doc/out/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	s := New(fp)

	for _, file := range files {
		doc := proto.SystemProfile{}
		err = tutil.LoadBson(dir+file.Name(), &doc)
		if err != nil {
			t.Fatalf("cannot load sample %s: %s", dir+file.Name(), err)
		}

		err = s.Add(doc)
		if err != nil {
			t.Errorf("Error processing doc: %s\n", err.Error())
		}
	}

	got := s.Queries()
	expect := Queries{}
	if tutil.ShouldUpdateSamples() {
		err := tutil.WriteJson(f, got)
		if err != nil {
			fmt.Printf("cannot update samples: %s", err.Error())
		}
	}
	err = tutil.LoadJson(f, &expect)
	if err != nil {
		t.Fatalf("cannot load expected data %s: %s", f, err)
	}
	if !reflect.DeepEqual(got, expect) {
		t.Errorf("s.Queries() = %#v, want %#v", got, expect)
	}
}

func TestAvailableMetrics(t *testing.T) {
	t.Parallel()

	var err error
	dirExpect := vars.RootPath + samples + "/expect/available_metrics/"
	dir := vars.RootPath + samples + "/doc/out/"

	versions := []string{
		"2.6.12",
		"3.0.15",
		"3.2.19",
		"3.4.12",
		"3.6.2",
	}

	samples := []string{
		"aggregate",
		"count",
		"count_with_query",
		"delete",
		"delete_all",
		"distinct",
		"find",
		"find_andrii",
		"find_empty",
		"findandmodify",
		"geonear",
		"group",
		"insert",
		"mapreduce",
		"update",
		"explain",
		"eval",
	}

	type sp struct {
		DocsExamined    *int `bson:"docsExamined" json:",omitempty"`
		NscannedObjects *int `bson:"nscannedObjects" json:",omitempty"`
		Millis          *int `bson:"millis" json:",omitempty"`
		Nreturned       *int `bson:"nreturned" json:",omitempty"`
		ResponseLength  *int `bson:"responseLength" json:",omitempty"`
	}

	data := map[string]map[string]sp{}

	for _, sample := range samples {
		for _, v := range versions {
			f := sample + "_" + v
			s := sp{}
			err = tutil.LoadBson(dir+f, &s)
			if err != nil {
				t.Fatalf("cannot load sample %s: %s", dir+f, err)
			}

			if data[sample] == nil {
				data[sample] = map[string]sp{}
			}
			data[sample][v] = s
		}
	}

	t.Run("available_metrics", func(t *testing.T) {
		got := data
		fExpect := dirExpect + "available_metrics"
		if tutil.ShouldUpdateSamples() {
			err := tutil.WriteJson(fExpect, got)
			if err != nil {
				fmt.Printf("cannot update samples: %s", err.Error())
			}
		}

		expect := map[string]map[string]sp{}
		err = tutil.LoadJson(fExpect, &expect)
		if err != nil {
			t.Fatalf("cannot load expected data %s: %s", fExpect, err)
		}

		if !reflect.DeepEqual(got, expect) {
			t.Errorf("s.Queries() = %#v, want %#v", got, expect)
		}
	})

	t.Run("cmd_metric", func(t *testing.T) {
		got := map[string]map[string][]string{}
		for s := range data {
			for v := range data[s] {
				if got[s] == nil {
					got[s] = map[string][]string{}
				}
				if data[s][v].Millis != nil {
					got[s]["Query Time"] = append(got[s]["Query Time"], v)
				}
				if data[s][v].DocsExamined != nil || data[s][v].NscannedObjects != nil {
					got[s]["Docs Scanned"] = append(got[s]["Docs Scanned"], v)
				}
				if data[s][v].Nreturned != nil {
					got[s]["Docs Returned"] = append(got[s]["Docs Returned"], v)
				}
				if data[s][v].ResponseLength != nil {
					got[s]["Bytes Sent"] = append(got[s]["Bytes Sent"], v)
				}
			}
		}

		metrics := []string{
			"Query Time",
			"Docs Scanned",
			"Docs Returned",
			"Bytes Sent",
		}
		for cmd := range got {
			for metric := range got[cmd] {
				if len(got[cmd][metric]) == len(versions) {
					got[cmd][metric] = []string{"yes"}
				} else {
					sort.Strings(got[cmd][metric])
				}
			}

			for _, metric := range metrics {
				if len(got[cmd][metric]) == 0 {
					got[cmd][metric] = []string{"no"}
				}
			}
		}

		fExpect := dirExpect + "cmd_metric"
		if tutil.ShouldUpdateSamples() {
			err := tutil.WriteJson(fExpect, got)
			if err != nil {
				fmt.Printf("cannot update samples: %s", err.Error())
			}
		}

		expect := map[string]map[string][]string{}
		err = tutil.LoadJson(fExpect, &expect)
		if err != nil {
			t.Fatalf("cannot load expected data %s: %s", fExpect, err)
		}

		if !reflect.DeepEqual(got, expect) {
			t.Errorf("s.Queries() = %s, want %s", got, expect)
		}

		data := got
		t.Run("md", func(t *testing.T) {
			type result struct {
				Metrics []string
				Samples []string
				Data    map[string]map[string][]string
			}
			r := result{
				Metrics: metrics,
				Samples: samples,
				Data:    data,
			}
			sort.Strings(r.Metrics)
			sort.Strings(r.Samples)

			tmpl := template.New("")
			tmpl = tmpl.Funcs(template.FuncMap{"join": strings.Join})
			tmpl, err := tmpl.Parse(`| |{{range .Metrics}} {{.}} |{{end}}
| - |{{range .Metrics}} - |{{end}}{{range $s := .Samples}}
| {{$s}} |{{range $m := $.Metrics}} {{join (index $.Data $s $m) ", "}} |{{end}}{{end}}`)
			if err != nil {
				panic(err)
			}
			var bufGot bytes.Buffer
			err = tmpl.Execute(&bufGot, r)
			if err != nil {
				panic(err)
			}
			got := bufGot.String()

			fExpect := dirExpect + "cmd_metric.md"
			if tutil.ShouldUpdateSamples() {
				err = ioutil.WriteFile(fExpect, bufGot.Bytes(), 0777)
				if err != nil {
					fmt.Printf("cannot update samples: %s", err.Error())
				}
			}

			buf, err := ioutil.ReadFile(fExpect)
			if err != nil {
				t.Fatalf("cannot load expected data %s: %s", fExpect, err)
			}
			expect := string(buf)

			if !reflect.DeepEqual(got, expect) {
				t.Errorf("got %s, want %s", got, expect)
			}
		})
	})
}
