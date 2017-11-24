package main

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"
	"text/template"
	"time"

	"github.com/pborman/getopt/v2"
	"github.com/percona/percona-toolkit/src/go/lib/profiling"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
	"github.com/percona/pmgo"
	"gopkg.in/mgo.v2/dbtest"
)

const (
	samples = "/src/go/tests/"
)

type testVars struct {
	RootPath string
}

var vars testVars
var Server dbtest.DBServer

func TestMain(m *testing.M) {
	var err error
	if vars.RootPath, err = tutil.RootPath(); err != nil {
		log.Printf("cannot get root path: %s", err.Error())
		os.Exit(1)
	}
	os.Exit(m.Run())

	// The tempdir is created so MongoDB has a location to store its files.
	// Contents are wiped once the server stops
	os.Setenv("CHECK_SESSIONS", "0")
	tempDir, _ := ioutil.TempDir("", "testing")
	Server.SetPath(tempDir)

	retCode := m.Run()

	Server.Session().Close()
	Server.Session().DB("samples").DropDatabase()

	// Stop shuts down the temporary server and removes data on disk.
	Server.Stop()

	// call with result of m.Run()
	os.Exit(retCode)
}

func TestIsProfilerEnabled(t *testing.T) {
	mongoDSN := os.Getenv("PT_TEST_MONGODB_DSN")
	if mongoDSN == "" {
		t.Skip("Skippping TestIsProfilerEnabled. It runs only in integration tests")
	}

	dialer := pmgo.NewDialer()
	di, _ := pmgo.ParseURL(mongoDSN)

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
				OutputFormat:    "text",
			},
		},
		{
			args: []string{TOOLNAME, "zapp.brannigan.net:27018/samples", "--help"},
			want: nil,
		},
		{
			args: []string{TOOLNAME, "zapp.brannigan.net:27018/samples"},
			want: &options{
				Host:            "zapp.brannigan.net:27018/samples",
				LogLevel:        DEFAULT_LOGLEVEL,
				OrderBy:         strings.Split(DEFAULT_ORDERBY, ","),
				SkipCollections: strings.Split(DEFAULT_SKIPCOLLECTIONS, ","),
				AuthDB:          DEFAULT_AUTHDB,
				Help:            false,
				OutputFormat:    "text",
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

type Data struct {
	bin string
	url string
}

func TestPTMongoDBQueryDigest(t *testing.T) {
	var err error

	binDir, err := ioutil.TempDir("/tmp", "pmm-client-test-bindir-")
	if err != nil {
		t.Error(err)
	}
	defer func() {
		err := os.RemoveAll(binDir)
		if err != nil {
			t.Error(err)
		}
	}()

	bin := binDir + "/pt-mongodb-query-digest"
	xVariables := map[string]string{
		"main.Build":     "<Build>",
		"main.Version":   "<Version>",
		"main.GoVersion": "<GoVersion>",
	}
	var ldflags []string
	for x, value := range xVariables {
		ldflags = append(ldflags, fmt.Sprintf("-X %s=%s", x, value))
	}
	cmd := exec.Command(
		"go",
		"build",
		"-o",
		bin,
		"-ldflags",
		strings.Join(ldflags, " "),
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	if err != nil {
		t.Error(err)
	}

	data := Data{
		bin: bin,
	}
	tests := []func(*testing.T, Data){
		testVersion,
		testEmptySystemProfile,
		testAllOperationsTemplate,
	}
	t.Run("pmm-admin", func(t *testing.T) {
		for _, f := range tests {
			f := f // capture range variable
			fName := runtime.FuncForPC(reflect.ValueOf(f).Pointer()).Name()
			t.Run(fName, func(t *testing.T) {
				// Clean up system.profile
				var err error
				data.url = "127.0.0.1/test"
				err = profiling.Disable(data.url)
				if err != nil {
					t.Error(err)
				}
				profiling.Drop(data.url)
				err = profiling.Enable(data.url)
				if err != nil {
					t.Error(err)
				}
				defer profiling.Disable(data.url)

				// t.Parallel()
				f(t, data)
			})
		}
	})

}

func testVersion(t *testing.T, data Data) {
	cmd := exec.Command(
		data.bin,
		"--version",
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Error(err)
	}
	expected := `pt-mongodb-query-digest
Version <Version>
Build: <Build> using <GoVersion>`

	assertRegexpLines(t, expected, string(output))
}

func testEmptySystemProfile(t *testing.T, data Data) {
	cmd := exec.Command(
		data.bin,
		data.url,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Error(err)
	}

	expected := "No queries found in profiler information for database \\\"test\\\""
	if !strings.Contains(string(output), expected) {
		t.Errorf("Empty system.profile.\nGot:\n%s\nWant:\n%s\n", string(output), expected)
	}
}

func testAllOperationsTemplate(t *testing.T, data Data) {
	dir := vars.RootPath + samples + "/doc/script/profile/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	fs := []string{}
	for _, file := range files {
		fs = append(fs, dir+file.Name())
	}
	sort.Strings(fs)
	err = run(fs...)
	if err != nil {
		t.Fatalf("cannot execute queries: %s", err)
	}

	// disable profiling so pt-mongodb-query digest reads rows from `system.profile`
	profiling.Disable(data.url)

	// run profiler
	cmd := exec.Command(
		data.bin,
		data.url,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Error(err)
	}

	queries := []stats.QueryStats{
		{
			ID:          "e357abe482dcc0cd03ab742741bf1c86",
			Namespace:   "test.coll",
			Operation:   "INSERT",
			Fingerprint: "INSERT coll",
		},
		{
			ID:          "c9b40ce564762834d12b0390a292645c",
			Namespace:   "test.coll",
			Operation:   "DROP",
			Fingerprint: "DROP coll drop",
		},
		{
			ID:          "db759bfd83441deecc71382323041ce6",
			Namespace:   "test.coll",
			Operation:   "GETMORE",
			Fingerprint: "GETMORE coll",
		},
		{
			ID:          "e72ad41302045bd6c2bcad76511f915a",
			Namespace:   "test.coll",
			Operation:   "REMOVE",
			Fingerprint: "REMOVE coll a,b",
		},
		{
			ID:          "30dbfbc89efd8cfd40774dff0266a28f",
			Namespace:   "test.coll",
			Operation:   "AGGREGATE",
			Fingerprint: "AGGREGATE coll a",
		},
		{
			ID:          "a6782ae38ef891d5506341a4b0ab2747",
			Namespace:   "test",
			Operation:   "EVAL",
			Fingerprint: "EVAL",
		},
		{
			ID:          "76d7662df07b44135ac3e07e44a6eb39",
			Namespace:   "",
			Operation:   "EXPLAIN",
			Fingerprint: "EXPLAIN",
		},
		{
			ID:          "e8a3f05a4bd3f0bfa7d38eb2372258b1",
			Namespace:   "test.coll",
			Operation:   "FINDANDMODIFY",
			Fingerprint: "FINDANDMODIFY coll a",
		},
		{
			ID:          "2a639e77efe3e68399ef9482575b3421",
			Namespace:   "test.coll",
			Operation:   "FIND",
			Fingerprint: "FIND coll",
		},
		{
			ID:          "fe0bf975a044fe47fd32b835ceba612d",
			Namespace:   "test.coll",
			Operation:   "FIND",
			Fingerprint: "FIND coll a",
		},
		{
			ID:          "20fe80188ec82c9d3c3dcf3f4817f8f9",
			Namespace:   "test.coll",
			Operation:   "FIND",
			Fingerprint: "FIND coll b,c",
		},
		{
			ID:          "02104210d67fe680273784d833f86831",
			Namespace:   "test.coll",
			Operation:   "FIND",
			Fingerprint: "FIND coll c,k,pad",
		},
		{
			ID:          "5efe4738d807c74b3980de76c37a0870",
			Namespace:   "test.coll",
			Operation:   "FIND",
			Fingerprint: "FIND coll k",
		},
		{
			ID:          "798d7c1cd25b63cb6a307126a25910d6",
			Namespace:   "test.system.js",
			Operation:   "FIND",
			Fingerprint: "FIND system.js",
		},
		{
			ID:          "c70403cbd55ffbb07f08c0cb77a24b19",
			Namespace:   "test.coll",
			Operation:   "GEONEAR",
			Fingerprint: "GEONEAR coll",
		},
		{
			ID:          "e4122a58c99ab0a4020ce7d195c5a8cb",
			Namespace:   "test.coll",
			Operation:   "DISTINCT",
			Fingerprint: "DISTINCT coll a,b",
		},
		{
			ID:          "ca8bb19386488570447f5753741fb494",
			Namespace:   "test.coll",
			Operation:   "GROUP",
			Fingerprint: "GROUP coll a,b",
		},
		{
			ID:          "10b8f47b366fbfd1fb01f8d17d75b1a2",
			Namespace:   "test.coll",
			Operation:   "COUNT",
			Fingerprint: "COUNT coll a",
		},
		{
			ID:          "cc3cb3824eea4094eb042f5ca76bd385",
			Namespace:   "test.coll",
			Operation:   "MAPREDUCE",
			Fingerprint: "MAPREDUCE coll a",
		},
		{
			ID:          "cba2dff0740762c6e5769f0e300df676",
			Namespace:   "test.coll",
			Operation:   "COUNT",
			Fingerprint: "COUNT coll",
		},
		{
			ID:          "f74a5120ac22d02120ccbf6d478b0dbc",
			Namespace:   "test.coll",
			Operation:   "UPDATE",
			Fingerprint: "UPDATE coll a",
		},
	}

	expected := `Profiler is disabled for the "test" database but there are \s*[0-9]+ documents in the system.profile collection.
Using those documents for the stats

# Totals
# Ratio    [0-9\.]+  \(docs scanned/returned\)
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)             (\s*[0-9]+)\s
# Exec Time ms         (\s*[0-9]+){8}\s
# Docs Scanned         (\s*[0-9\.]+){8}\s
# Docs Returned        (\s*[0-9\.]+){8}\s
# Bytes sent           (\s*[0-9\.K]+){8}(K|\s)
#\s
`

	queryTpl := `
# Query [0-9]+:  [0-9\.]+ QPS, ID {{.ID}}
# Ratio    [0-9\.]+  \(docs scanned/returned\)
# Time range: .* to .*
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)             (\s*[0-9]+)\s
# Exec Time ms         (\s*[0-9]+){8}\s
# Docs Scanned         (\s*[0-9\.]+){8}\s
# Docs Returned        (\s*[0-9\.]+){8}\s
# Bytes sent           (\s*[0-9\.K]+){8}(K|\s)
# String:
# Namespace           {{.Namespace}}
# Operation           {{.Operation}}
# Fingerprint         {{.Fingerprint}}
# Query               .*

`

	tpl, _ := template.New("query").Parse(queryTpl)
	for _, query := range queries {
		buf := bytes.Buffer{}
		err := tpl.Execute(&buf, query)
		if err != nil {
			t.Error(err)
		}

		expected += buf.String()
	}
	expected += "\n" // Looks like we expect additional line

	assertRegexpLines(t, expected, string(output))
}

// assertRegexpLines matches regexp line by line to corresponding line of text
func assertRegexpLines(t *testing.T, rx string, str string, msgAndArgs ...interface{}) bool {
	expectedScanner := bufio.NewScanner(strings.NewReader(rx))
	defer func() {
		if err := expectedScanner.Err(); err != nil {
			t.Fatal(err)
		}
	}()

	actualScanner := bufio.NewScanner(strings.NewReader(str))
	defer func() {
		if err := actualScanner.Err(); err != nil {
			t.Fatal(err)
		}
	}()

	ok := true
	for {
		asOk := actualScanner.Scan()
		esOk := expectedScanner.Scan()

		switch {
		case asOk && esOk:
			ok, err := regexp.MatchString("^"+expectedScanner.Text()+"$", actualScanner.Text())
			if err != nil {
				t.Error(err)
			}
			if !ok {
				t.Errorf("regexp '%s' doesn't match '%s'", expectedScanner.Text(), actualScanner.Text())
			}
		case asOk:
			t.Errorf("didn't expect more lines but got: %s", actualScanner.Text())
			ok = false
		case esOk:
			t.Errorf("didn't got line but expected it to match against: %s", expectedScanner.Text())
			ok = false
		default:
			return ok
		}
	}
}

func run(arg ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "mongo", arg...).Run()
}
