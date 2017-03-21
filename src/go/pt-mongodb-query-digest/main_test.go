package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/pborman/getopt/v2"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"

	mgo "gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/dbtest"
)

var Server dbtest.DBServer

func TestMain(m *testing.M) {
	// The tempdir is created so MongoDB has a location to store its files.
	// Contents are wiped once the server stops
	os.Setenv("CHECK_SESSIONS", "0")
	tempDir, _ := ioutil.TempDir("", "testing")
	Server.SetPath(tempDir)

	dat, err := ioutil.ReadFile("test/sample/system.profile.json")
	if err != nil {
		fmt.Printf("cannot load fixtures: %s", err)
		os.Exit(1)
	}

	var docs []proto.SystemProfile
	err = json.Unmarshal(dat, &docs)
	c := Server.Session().DB("samples").C("system_profile")
	for _, doc := range docs {
		c.Insert(doc)
	}

	retCode := m.Run()

	Server.Session().Close()
	Server.Session().DB("samples").DropDatabase()

	// Stop shuts down the temporary server and removes data on disk.
	Server.Stop()

	// call with result of m.Run()
	os.Exit(retCode)
}

func TestCalcStats(t *testing.T) {
	it := Server.Session().DB("samples").C("system_profile").Find(nil).Sort("Ts").Iter()
	data := getData(it, []docsFilter{})
	s := calcStats(data[0].NScanned)

	want := statistics{Pct: 0, Total: 159, Min: 79, Max: 80, Avg: 79.5, Pct95: 80, StdDev: 0.5, Median: 79.5}

	if !reflect.DeepEqual(s, want) {
		t.Errorf("error in calcStats: got:\n%#v\nwant:\n%#v\n", s, want)
	}

	wantTotals := stat{
		ID:             "",
		Fingerprint:    "",
		Namespace:      "",
		Query:          map[string]interface{}(nil),
		Count:          0,
		TableScan:      false,
		NScanned:       []float64{79, 80},
		NReturned:      []float64{79, 80},
		QueryTime:      []float64{27, 28},
		ResponseLength: []float64{109, 110},
		LockTime:       nil,
		BlockedTime:    nil,
		FirstSeen:      time.Time{},
		LastSeen:       time.Time{},
	}

	totals := getTotals(data[0:1])

	if !reflect.DeepEqual(totals, wantTotals) {
		t.Errorf("error in calcStats: got:\n%#v\nwant:\n:%#v\n", totals, wantTotals)
	}
	var wantTotalCount int = 2
	var wantTotalScanned, wantTotalReturned, wantTotalQueryTime, wantTotalBytes float64 = 159, 159, 55, 219

	totalCount, totalScanned, totalReturned, totalQueryTime, totalBytes := calcTotals(data[0:1])

	if totalCount != wantTotalCount {
		t.Errorf("invalid total count. Want %v, got %v\n", wantTotalCount, totalCount)
	}

	if totalScanned != wantTotalScanned {
		t.Errorf("invalid total count. Want %v, got %v\n", wantTotalScanned, totalScanned)
	}
	if totalReturned != wantTotalReturned {
		t.Errorf("invalid total count. Want %v, got %v\n", wantTotalReturned, totalReturned)
	}
	if totalQueryTime != wantTotalQueryTime {
		t.Errorf("invalid total count. Want %v, got %v\n", wantTotalQueryTime, totalQueryTime)
	}
	if totalBytes != wantTotalBytes {
		t.Errorf("invalid total count. Want %v, got %v\n", wantTotalBytes, totalBytes)
	}
}

func TestGetData(t *testing.T) {
	it := Server.Session().DB("samples").C("system_profile").Find(nil).Iter()
	tests := []struct {
		name string
		i    iter
		want []stat
	}{
		{
			name: "test 1",
			i:    it,
			want: []stat{
				stat{
					ID:             "6c3fff4804febd156700a06f9a346162",
					Operation:      "query",
					Fingerprint:    "find,limit",
					Namespace:      "samples.col1",
					Query:          map[string]interface{}{"find": "col1", "limit": float64(2)},
					Count:          2,
					TableScan:      false,
					NScanned:       []float64{79, 80},
					NReturned:      []float64{79, 80},
					QueryTime:      []float64{27, 28},
					ResponseLength: []float64{109, 110},
					LockTime:       times(nil),
					BlockedTime:    times(nil),
					FirstSeen:      time.Date(2016, time.November, 8, 13, 46, 27, 0, time.UTC).Local(),
					LastSeen:       time.Date(2016, time.November, 8, 13, 46, 27, 0, time.UTC).Local(),
				},
				stat{
					ID:             "fdcea004122ddb225bc56de417391e25",
					Operation:      "query",
					Fingerprint:    "find",
					Namespace:      "samples.col1",
					Query:          map[string]interface{}{"find": "col1"},
					Count:          8,
					TableScan:      false,
					NScanned:       []float64{71, 72, 73, 74, 75, 76, 77, 78},
					NReturned:      []float64{71, 72, 73, 74, 75, 76, 77, 78},
					QueryTime:      []float64{19, 20, 21, 22, 23, 24, 25, 26},
					ResponseLength: []float64{101, 102, 103, 104, 105, 106, 107, 108},
					LockTime:       times(nil),
					BlockedTime:    times(nil),
					FirstSeen:      time.Date(2016, time.November, 8, 13, 46, 27, 0, time.UTC).Local(),
					LastSeen:       time.Date(2016, time.November, 8, 13, 46, 27, 0, time.UTC).Local(),
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := getData(tt.i, []docsFilter{})
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got\n%#v\nwant\n%#v", got, tt.want)
			}
		})
	}
}

func TestUptime(t *testing.T) {

	session := pmgo.NewSessionManager(Server.Session())
	time.Sleep(1500 * time.Millisecond)
	if uptime(session) <= 0 {
		t.Error("uptime is 0")
	}
	session.Close()

}

func TestFingerprint(t *testing.T) {
	tests := []struct {
		name  string
		query map[string]interface{}
		want  string
	}{
		{
			query: map[string]interface{}{"query": map[string]interface{}{}, "orderby": map[string]interface{}{"ts": -1}},
			want:  "orderby,query,ts",
		},
		{
			query: map[string]interface{}{"find": "system.profile", "filter": map[string]interface{}{}, "sort": map[string]interface{}{"$natural": 1}},
			want:  "$natural",
		},
		{

			query: map[string]interface{}{"collection": "system.profile", "batchSize": 0, "getMore": 18531768265},
			want:  "batchSize,collection,getMore",
		},
		/*
			  Main test case:
			  Got Query field:
			  {
				  "filter": {
				     "aSampleDate":{
				        "$gte":1427846400000,
				        "$lte":1486511999999},
				        "brotherId":"25047dd6f52711e6b3c7c454",
				        "examined":true,
				        "sampleResponse.sampleScore.selectedScore":{
				            "$in":[5,4,3,2,1]
				        }
				  },
				  "find": "transModifiedTags",
				  "ntoreturn":10,
				  "projection":{
				     "$sortKey":{
				        "$meta":"sortKey"
				     }
				  },
				  "shardVersion":[571230652140,"6f7dcd9af52711e6ad7cc454"],
				  "sort":{"aSampleDate":-1}
			  }

			  Want fingerprint:
			  aSampleDate,brotherId,examined,sampleResponse.sampleScore.selectedScore

			  Why?
			  1) It is MongoDb 3.2+ (has filter instead of $query)
			  2) From the "filter" map, we are removing all keys starting with $
			  3) The key 'aSampleDate' exists in the "sort" map but it is not in the "filter" keys
			     so it has been added to the final fingerprint
		*/
		{
			query: map[string]interface{}{"sort": map[string]interface{}{"aSampleDate": -1}, "filter": map[string]interface{}{"aSampleDate": map[string]interface{}{"$gte": 1.4278464e+12, "$lte": 1.486511999999e+12}, "brotherId": "25047dd6f52711e6b3c7c454", "examined": true, "sampleResponse.sampleScore.selectedScore": map[string]interface{}{"$in": []interface{}{5, 4, 3, 2, 1}}}, "find": "transModifiedTags", "ntoreturn": 10, "projection": map[string]interface{}{"$sortKey": map[string]interface{}{"$meta": "sortKey"}}, "shardVersion": []interface{}{5.7123065214e+11, "6f7dcd9af52711e6ad7cc454"}},
			want:  "aSampleDate,brotherId,examined,sampleResponse.sampleScore.selectedScore",
		},
	}
	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got, err := fingerprint(tt.query); got != tt.want || err != nil {
				t.Errorf("fingerprint  case #%d:\n got %v,\nwant %v\nerror: %v\n", i, got, tt.want, err)
			}
		})
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

func TestIsProfilerEnabled(t *testing.T) {
	mongoDSN := os.Getenv("PT_TEST_MONGODB_DSN")
	if mongoDSN == "" {
		t.Skip("Skippping TestIsProfilerEnabled. It runs only in integration tests")
	}

	dialer := pmgo.NewDialer()
	di, _ := mgo.ParseURL(mongoDSN)
	enabled, err := isProfilerEnabled(dialer, di)

	if err != nil {
		t.Errorf("Cannot check if profiler is enabled: %s", err.Error())
	}
	if enabled != true {
		t.Error("Profiler must be enabled")
	}

}

func TestParseArgs(t *testing.T) {
	tests := []struct {
		args []string
		want *options
	}{
		{
			args: []string{TOOLNAME}, // arg[0] is the command itself
			want: &options{
				Host:            DEFAULT_HOST,
				LogLevel:        DEFAULT_LOGLEVEL,
				OrderBy:         strings.Split(DEFAULT_ORDERBY, ","),
				SkipCollections: strings.Split(DEFAULT_SKIPCOLLECTIONS, ","),
				AuthDB:          DEFAULT_AUTHDB,
			},
		},
		{
			args: []string{TOOLNAME, "zapp.brannigan.net:27018/samples", "--help"},
			want: &options{
				Host:            "zapp.brannigan.net:27018/samples",
				LogLevel:        DEFAULT_LOGLEVEL,
				OrderBy:         strings.Split(DEFAULT_ORDERBY, ","),
				SkipCollections: strings.Split(DEFAULT_SKIPCOLLECTIONS, ","),
				AuthDB:          DEFAULT_AUTHDB,
				Help:            true,
			},
		},
	}
	for i, test := range tests {
		getopt.Reset()
		os.Args = test.args
		got, err := getOptions()
		if err != nil {
			t.Errorf("error parsing command line arguments: %s", err.Error())
		}
		if !reflect.DeepEqual(got, test.want) {
			t.Errorf("invalid command line options test %d\ngot %+v\nwant %+v\n", i, got, test.want)
		}
	}

}
