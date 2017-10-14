package main

import (
	"bufio"
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"reflect"
	"regexp"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/pborman/getopt/v2"
	"github.com/percona/percona-toolkit/src/go/lib/profiling"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
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
				err = profiling.Drop(data.url)
				if err != nil {
					t.Error(err)
				}
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

	expected := `pt-mongodb-query-digest .+
Host: ` + data.url + `
Skipping profiled queries on these collections: \[system\.profile\]


# Totals
# Ratio    0.00  \(docs scanned/returned\)
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)                     0\s
# Exec Time ms           0       NaN         NaN         NaN         NaN         NaN         NaN         NaN\s
# Docs Scanned           0       NaN         NaN         NaN         NaN         NaN         NaN         NaN\s
# Docs Returned          0       NaN         NaN         NaN         NaN         NaN         NaN         NaN\s
# Bytes recv             0       NaN         NaN         NaN         NaN         NaN         NaN         NaN\s
#\s

`

	assertRegexpLines(t, expected, string(output))
}

func testAllOperationsTemplate(t *testing.T, data Data) {
	dir := vars.RootPath + samples + "/doc/script/profile/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	for _, file := range files {
		err := run(dir + file.Name())
		if err != nil {
			t.Fatalf("cannot execute query '%s': %s", dir+file.Name(), err)
		}

	}
	cmd := exec.Command(
		data.bin,
		data.url,
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Error(err)
	}

	expected := `pt-mongodb-query-digest .+
Host: ` + data.url + `
Skipping profiled queries on these collections: \[system\.profile\]


# Totals
# Ratio    0.00  \(docs scanned/returned\)
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)                   111\s
# Exec Time ms         (\s*[0-9]+){8}\s
# Docs Scanned         100     53.00        0.00       47.00        0.48        0.00        4.46        0.00\s
# Docs Returned          0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# Bytes recv           100      3.12K       0.00       29.00       28.14       29.00        4.77       29.00\s
#\s

# Query 1:  0.00 QPS, ID a7ce8dee16beadb767484112e6b29af3
# Ratio    0.00  \(docs scanned/returned\)
# Time range: .* to .*
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)                   107\s
# Exec Time ms         (\s*[0-9]+){8}\s
# Docs Scanned           0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# Docs Returned          0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# Bytes recv            99      3.10K      29.00       29.00       29.00       29.00        0.00       29.00\s
# String:
# Namespaces          test.coll
# Operation           insert
# Fingerprint         INSERT coll
# Query               {"ns":"test.coll","op":"insert","query":{"insert":"coll","documents":\[{"_id":{"\$oid":".+"},"a":9}\],"ordered":true}}


# Query 2:  0.00 QPS, ID bab52c8aa977c96ecd148c015ae07c42
# Ratio    0.00  \(docs scanned/returned\)
# Time range: .* to .*
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)                     2\s
# Exec Time ms         (\s*[0-9]+){8}\s
# Docs Scanned          98     52.00        5.00       47.00       26.00       47.00       21.00       26.00\s
# Docs Returned          0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# Bytes recv             0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# String:
# Namespaces          test.coll
# Operation           remove
# Fingerprint         REMOVE coll a,b
# Query               {"ns":"test.coll","op":"remove","query":{"a":{"\$gte":2},"b":{"\$gte":2}}}


# Query 3:  0.00 QPS, ID ffd83008fd6affc7c07053f583dea3e0
# Ratio    0.00  \(docs scanned/returned\)
# Time range: .* to .*
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)                     1\s
# Exec Time ms         (\s*[0-9]+){8}\s
# Docs Scanned           0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# Docs Returned          0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# Bytes recv             1     20.00       20.00       20.00       20.00       20.00        0.00       20.00\s
# String:
# Namespaces          test.system.js
# Operation           query
# Fingerprint         FIND system.js find
# Query               {"ns":"test.system.js","op":"query","query":{"find":"system.js"}}


# Query 4:  0.00 QPS, ID 27cb39e62745b1ff4121b4bf6f21fb12
# Ratio    0.00  \(docs scanned/returned\)
# Time range: .* to .*
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count \(docs\)                     1\s
# Exec Time ms         (\s*[0-9]+){8}\s
# Docs Scanned           2      1.00        1.00        1.00        1.00        1.00        0.00        1.00\s
# Docs Returned          0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# Bytes recv             0      0.00        0.00        0.00        0.00        0.00        0.00        0.00\s
# String:
# Namespaces          test.coll
# Operation           update
# Fingerprint         UPDATE coll a
# Query               {"ns":"test.coll","op":"update","query":{"a":{"\$gte":2}},"updateobj":{"\$set":{"c":1},"\$inc":{"a":-10}}}

`

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

func run(filename string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "mongo", filename).Run()

}
