// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package main

import (
	"context"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/pborman/getopt"
	"github.com/stretchr/testify/require"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
)

func TestGetHostInfo(t *testing.T) {
	testCases := []struct {
		name string
		port string
		want []string
	}{
		{
			name: "from_mongos",
			port: tu.MongoDBMongosPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17004", "127.0.0.1:17005", "127.0.0.1:17007"},
		},
		{
			name: "from_mongod",
			port: tu.MongoDBShard1PrimaryPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17003"},
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			client, err := tu.TestClient(ctx, test.port)
			if err != nil {
				t.Fatalf("cannot get a new MongoDB client: %s", err)
			}

			_, err = getHostInfo(ctx, client)
			if err != nil {
				t.Errorf("getHostnames: %v", err)
			}
		})
	}
}

func TestGetHostInfoResult(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := tu.TestClient(ctx, tu.MongoDBShard1PrimaryPort)
	require.NoError(t, err, "cannot get a new MongoDB client")

	host, err := getHostInfo(ctx, client)
	require.NoError(t, err, "getHostInfo error")
	require.NotEmpty(t, host)
}

func TestClusterWideInfo(t *testing.T) {
	testCases := []struct {
		name string
		port string
		want []string
	}{
		{
			name: "from_mongos",
			port: tu.MongoDBMongosPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17004", "127.0.0.1:17005", "127.0.0.1:17007"},
		},
		{
			name: "from_mongod",
			port: tu.MongoDBShard1PrimaryPort,
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17003"},
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			client, err := tu.TestClient(ctx, test.port)
			if err != nil {
				t.Fatalf("cannot get a new MongoDB client: %s", err)
			}

			_, err = getClusterwideInfo(ctx, client)
			if err != nil {
				t.Errorf("getClisterWideInfo error: %v", err)
			}
		})
	}
}

func TestParseArgs(t *testing.T) {
	tests := []struct {
		args []string
		want *cliOptions
	}{
		{
			args: []string{toolname}, // arg[0] is the command itself
			want: &cliOptions{
				Host:               DefaultHost,
				LogLevel:           DefaultLogLevel,
				AuthDB:             DefaultAuthDB,
				RunningOpsSamples:  DefaultRunningOpsSamples,
				RunningOpsInterval: DefaultRunningOpsInterval,
				OutputFormat:       "text",
			},
		},
		{
			args: []string{toolname, "zapp.brannigan.net:27018/samples", "--help"},
			want: nil,
		},
	}

	// Capture stdout to not to show help
	old := os.Stdout // keep backup of the real stdout
	_, w, _ := os.Pipe()
	os.Stdout = w

	for i, test := range tests {
		getopt.Reset()
		os.Args = test.args
		got, err := parseFlags()
		if err != nil {
			t.Errorf("error parsing command line arguments: %s", err.Error())
		}
		if !reflect.DeepEqual(got, test.want) {
			t.Errorf("invalid command line options test %d\ngot %+v\nwant %+v\n", i, got, test.want)
		}
	}

	os.Stdout = old
}

func TestGetMongosInfo(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := tu.TestClient(ctx, tu.MongoDBMongosPort)
	require.NoError(t, err)

	info, err := getMongosInfo(ctx, client)
	require.NoError(t, err)
	require.NotNil(t, info)
	require.NotEmpty(t, info.Instances)

	for _, m := range info.Instances {
		require.NotEmpty(t, m.Name)
		require.NotEmpty(t, m.Version)
		require.NotEqual(t, 0, m.UpTime)
		require.False(t, m.LastPing.IsZero())
	}
}
