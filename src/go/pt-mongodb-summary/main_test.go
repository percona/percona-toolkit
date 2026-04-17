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
	"testing"
	"time"

	"context"
	"os"
	"reflect"

	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/mongo/options"

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

func TestParseFlags(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		want    *cliOptions
		wantErr bool
	}{
		{
			name: "Default values",
			args: []string{toolname},
			want: &cliOptions{
				Host:               "",
				LogLevel:           DefaultLogLevel,
				AuthDB:             DefaultAuthDB,
				RunningOpsSamples:  DefaultRunningOpsSamples,
				RunningOpsInterval: DefaultRunningOpsInterval,
				OutputFormat:       "text",
			},
		},
		{
			name: "URI only",
			args: []string{toolname, "--uri", "mongodb://test:27017"},
			want: &cliOptions{
				URI:                "mongodb://test:27017",
				LogLevel:           DefaultLogLevel,
				AuthDB:             DefaultAuthDB,
				RunningOpsSamples:  DefaultRunningOpsSamples,
				RunningOpsInterval: DefaultRunningOpsInterval,
				OutputFormat:       "text",
			},
		},
		{
			name: "Legacy positional host:port",
			args: []string{toolname, "test.example.com:27019"},
			want: &cliOptions{
				Host:               "test.example.com",
				Port:               "27019",
				LogLevel:           DefaultLogLevel,
				AuthDB:             DefaultAuthDB,
				RunningOpsSamples:  DefaultRunningOpsSamples,
				RunningOpsInterval: DefaultRunningOpsInterval,
				OutputFormat:       "text",
			},
		},
		{
			name:    "Error: URI and Host together",
			args:    []string{toolname, "--uri", "mongodb://test", "--host", "localhost"},
			wantErr: true,
		},
		{
			name:    "Error: Positional arg and Host flag together",
			args:    []string{toolname, "--host", "newhost", "legacy:27017"},
			wantErr: true,
		},
		{
			name: "Help flag returns nil options",
			args: []string{toolname, "--help"},
			want: nil,
		},
	}

	// Backup and silence stdout
	oldStdout := os.Stdout
	_, w, _ := os.Pipe()
	os.Stdout = w
	defer func() { os.Stdout = oldStdout }()

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			getopt.Reset()
			os.Args = tt.args

			got, err := parseFlags()

			if tt.wantErr {
				if err == nil {
					t.Errorf("expected error but got none")
				}
				return
			}

			if err != nil {
				t.Errorf("unexpected error: %v", err)
				return
			}

			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("mismatch:\ngot:  %+v\nwant: %+v", got, tt.want)
			}
		})
	}
}

func TestGetClientOptions(t *testing.T) {
	tests := []struct {
		name     string
		opts     *cliOptions
		wantErr  bool
		validate func(*testing.T, *options.ClientOptions)
	}{
		{
			name: "Default values when everything is empty",
			opts: &cliOptions{},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, []string{"localhost:27017"}, co.Hosts)
				assert.Nil(t, co.Auth)
			},
		},
		{
			name: "Priority to URI",
			opts: &cliOptions{
				URI: "mongodb://remote-host:28000",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, []string{"remote-host:28000"}, co.Hosts)
			},
		},
		{
			name: "Flags override Auth in URI",
			opts: &cliOptions{
				URI:      "mongodb://old-user:old-pass@localhost:27017",
				User:     "new-user",
				Password: "new-password",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "new-user", co.Auth.Username)
				assert.Equal(t, "new-password", co.Auth.Password)
			},
		},
		{
			name: "Only host and port flags",
			opts: &cliOptions{
				Host: "127.0.0.1",
				Port: "27019",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, []string{"127.0.0.1:27019"}, co.Hosts)
			},
		},
		{
			name: "Invalid URI should return error",
			opts: &cliOptions{
				URI: "not-a-valid-uri",
			},
			wantErr: true,
		},
		{
			name: "AuthDB via URI (check if preserved)",
			opts: &cliOptions{
				URI: "mongodb://user@localhost:27017/admin?authSource=custom_db",
			},
			validate: func(t *testing.T, co *options.ClientOptions) {
				assert.Equal(t, "user", co.Auth.Username)
				assert.Equal(t, "custom_db", co.Auth.AuthSource)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := getClientOptions(tt.opts)

			if tt.wantErr {
				assert.Error(t, err)
				return
			}

			assert.NoError(t, err)
			assert.NotNil(t, got)

			if tt.validate != nil {
				tt.validate(t, got)
			}

			assert.NotNil(t, got.ServerSelectionTimeout)
			assert.True(t, *got.Direct)
		})
	}
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
