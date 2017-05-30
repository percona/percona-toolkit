package main

import (
	"io/ioutil"
	"os"
	"reflect"
	"strings"
	"testing"

	"github.com/pborman/getopt/v2"
	"github.com/percona/pmgo"

	"gopkg.in/mgo.v2/dbtest"
)

var Server dbtest.DBServer

func TestMain(m *testing.M) {
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
