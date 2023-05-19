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

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/pborman/getopt"
	"github.com/percona/percona-toolkit/src/go/lib/profiling"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
)

const (
	samples = "/src/go/tests/"
)

type testVars struct {
	RootPath string
}

type Data struct {
	bin string
	url string
	db  string
}

var vars testVars
var client *mongo.Client

func TestMain(m *testing.M) {
	var err error
	if vars.RootPath, err = tutil.RootPath(); err != nil {
		log.Printf("cannot get root path: %s", err.Error())
		os.Exit(1)
	}

	client, err = mongo.Connect(context.TODO(), options.Client().ApplyURI(os.Getenv("PT_TEST_MONGODB_DSN")))
	if err != nil {
		log.Printf("Cannot connect: %s", err.Error())
		os.Exit(1)
	}

	err = profiling.Disable(context.TODO(), client, "test")
	if err != nil {
		log.Printf("Cannot disable profile: %s", err.Error())
		os.Exit(1)
	}
	err = profiling.Drop(context.TODO(), client, "test")
	if err != nil {
		log.Printf("Cannot drop profile database: %s", err.Error())
		os.Exit(1)
	}
	err = profiling.Enable(context.TODO(), client, "test")
	if err != nil {
		log.Printf("Cannot enable profile: %s", err.Error())
		os.Exit(1)
	}

	retCode := m.Run()

	err = profiling.Disable(context.TODO(), client, "test")
	if err != nil {
		log.Printf("Cannot disable profile: %s", err.Error())
		os.Exit(1)
	}

	os.Exit(retCode)
}

func TestIsProfilerEnabled(t *testing.T) {
	mongoDSN := os.Getenv("PT_TEST_MONGODB_DSN")
	if mongoDSN == "" {
		t.Skip("Skippping TestIsProfilerEnabled. It runs only in integration tests")
	}

	enabled, err := isProfilerEnabled(context.TODO(), options.Client().ApplyURI(mongoDSN), "test")
	//
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
		want *cliOptions
	}{
		{
			args: []string{TOOLNAME}, // arg[0] is the command itself
			want: &cliOptions{
				Host:            "mongodb://" + DEFAULT_HOST,
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
			want: &cliOptions{
				Host:            "mongodb://zapp.brannigan.net:27018/samples",
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
		//disabling Stdout to avoid printing help message to the screen
		sout := os.Stdout
		os.Stdout = nil
		got, err := getOptions()
		os.Stdout = sout
		if err != nil {
			t.Errorf("error parsing command line arguments: %s", err.Error())
		}
		if !reflect.DeepEqual(got, test.want) {
			t.Errorf("invalid command line options test %d\ngot %+v\nwant %+v\n", i, got, test.want)
		}
	}
}

func TestPTMongoDBQueryDigest(t *testing.T) {
	var err error
	//
	binDir, err := ioutil.TempDir("/tmp", "pt-test-bindir")
	if err != nil {
		t.Error(err)
	}
	defer func() {
		err := os.RemoveAll(binDir)
		if err != nil {
			t.Error(err)
		}
	}()
	//
	bin := binDir + "/pt-mongodb-query-digest"
	xVariables := map[string]string{
		"main.Build":     "<Build>",
		"main.Version":   "<Version>",
		"main.GoVersion": "<GoVersion>",
		"main.Commit":    "<Commit>",
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
	//
	data := Data{
		bin: bin,
		url: os.Getenv("PT_TEST_MONGODB_DSN"),
		db:  "test",
	}
	tests := []func(*testing.T, Data){
		testVersion,
		testEmptySystemProfile,
		testAllOperationsTemplate,
	}

	t.Run("pt-mongodb-query-digest", func(t *testing.T) {
		for _, f := range tests {
			f := f // capture range variable
			fName := runtime.FuncForPC(reflect.ValueOf(f).Pointer()).Name()
			t.Run(fName, func(t *testing.T) {
				// Clean up system.profile
				var err error
				err = profiling.Disable(context.TODO(), client, data.db)
				if err != nil {
					t.Error(err)
				}
				profiling.Drop(context.TODO(), client, data.db)
				err = profiling.Enable(context.TODO(), client, data.db)
				if err != nil {
					t.Error(err)
				}
				defer profiling.Disable(context.TODO(), client, data.db)
				//
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
Build: <Build> using <GoVersion>
Commit: <Commit>`
	//
	assertRegexpLines(t, expected, string(output))
}

func testEmptySystemProfile(t *testing.T, data Data) {
	cmd := exec.Command(
		data.bin,
		data.url,
		"--database="+data.db,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Error(err)
	}
	//
	expected := "No queries found in profiler information for database \\\"" + data.db + "\\\""
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
	//
	fs := []string{}
	for _, file := range files {
		fs = append(fs, dir+file.Name())
	}
	sort.Strings(fs)
	fs = append([]string{os.Getenv("PT_TEST_MONGODB_DSN")}, fs...)
	err = run(fs...)
	if err != nil {
		t.Fatalf("cannot execute queries: %s", err)
	}
	//
	// disable profiling so pt-mongodb-query digest reads rows from `system.profile`

	profiling.Disable(context.TODO(), client, data.db)
	//
	// run profiler
	cmd := exec.Command(
		data.bin,
		data.url,
		"--database="+data.db,
	)
	//
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Error(err)
	}
	//
	queries := []stats.QueryStats{
		{
			ID:          "e357abe482dcc0cd03ab742741bf1c86",
			Namespace:   "test.coll",
			Operation:   "INSERT",
			Fingerprint: "INSERT coll",
		},
		{
			ID:          "22eda5c05290c1af6dbffd8c38aceff6",
			Namespace:   "test.coll",
			Operation:   "DROP",
			Fingerprint: "DROP coll",
		},
		{
			ID:          "ba1d8c1620d1aaf36c1010c809ec462b",
			Namespace:   "test.coll",
			Operation:   "CREATEINDEXES",
			Fingerprint: "CREATEINDEXES coll",
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
			ID:          "2a639e77efe3e68399ef9482575b3421",
			Namespace:   "test.coll",
			Operation:   "FIND",
			Fingerprint: "FIND coll",
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
			ID:          "30dbfbc89efd8cfd40774dff0266a28f",
			Namespace:   "test.coll",
			Operation:   "AGGREGATE",
			Fingerprint: "AGGREGATE coll a",
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
			ID:          "e4122a58c99ab0a4020ce7d195c5a8cb",
			Namespace:   "test.coll",
			Operation:   "DISTINCT",
			Fingerprint: "DISTINCT coll a,b",
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
	//
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
	//
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
	//
	tpl, _ := template.New("query").Parse(queryTpl)
	for _, query := range queries {
		buf := bytes.Buffer{}
		err := tpl.Execute(&buf, query)
		if err != nil {
			t.Error(err)
		}
		//
		expected += buf.String()
	}
	expected += "\n" // Looks like we expect additional line
	//
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
	//
	actualScanner := bufio.NewScanner(strings.NewReader(str))
	defer func() {
		if err := actualScanner.Err(); err != nil {
			t.Fatal(err)
		}
	}()
	//
	ok := true
	for {
		asOk := actualScanner.Scan()
		esOk := expectedScanner.Scan()
		//
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
