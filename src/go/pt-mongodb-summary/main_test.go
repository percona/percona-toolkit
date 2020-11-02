package main

import (
	"context"
	"fmt"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/pborman/getopt"
	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func TestGetHostInfo(t *testing.T) {
	testCases := []struct {
		name string
		uri  string
		want []string
	}{
		{
			name: "from_mongos",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBMongosPort),
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17004", "127.0.0.1:17005", "127.0.0.1:17007"},
		},
		{
			name: "from_mongod",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard1PrimaryPort),
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17003"},
		},
		{
			name: "from_non_sharded",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard3PrimaryPort),
			want: []string{"127.0.0.1:17021", "127.0.0.1:17022", "127.0.0.1:17023"},
		},
	}
	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			client, err := mongo.NewClient(options.Client().ApplyURI(test.uri))
			if err != nil {
				t.Fatalf("cannot get a new MongoDB client: %s", err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			err = client.Connect(ctx)
			if err != nil {
				t.Fatalf("Cannot connect to MongoDB: %s", err)
			}

			_, err = getHostInfo(ctx, client)
			if err != nil {
				t.Errorf("getHostnames: %v", err)
			}
		})
	}
}

func TestClusterWideInfo(t *testing.T) {
	testCases := []struct {
		name string
		uri  string
		want []string
	}{
		{
			name: "from_mongos",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBMongosPort),
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17004", "127.0.0.1:17005", "127.0.0.1:17007"},
		},
		{
			name: "from_mongod",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard1PrimaryPort),
			want: []string{"127.0.0.1:17001", "127.0.0.1:17002", "127.0.0.1:17003"},
		},
		{
			name: "from_non_sharded",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard3PrimaryPort),
			want: []string{"127.0.0.1:17021", "127.0.0.1:17022", "127.0.0.1:17023"},
		},
	}
	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			client, err := mongo.NewClient(options.Client().ApplyURI(test.uri))
			if err != nil {
				t.Fatalf("cannot get a new MongoDB client: %s", err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			err = client.Connect(ctx)
			if err != nil {
				t.Fatalf("Cannot connect to MongoDB: %s", err)
			}

			_, err = getClusterwideInfo(ctx, client)
			if err != nil {
				t.Errorf("getClisterWideInfo error: %v", err)
			}
		})
	}
}

func addToCounters(ss proto.ServerStatus, increment int64) proto.ServerStatus {
	ss.Opcounters.Command += increment
	ss.Opcounters.Delete += increment
	ss.Opcounters.GetMore += increment
	ss.Opcounters.Insert += increment
	ss.Opcounters.Query += increment
	ss.Opcounters.Update += increment
	return ss
}

func TestParseArgs(t *testing.T) {
	tests := []struct {
		args []string
		want *cliOptions
	}{
		{
			args: []string{TOOLNAME}, // arg[0] is the command itself
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
			args: []string{TOOLNAME, "zapp.brannigan.net:27018/samples", "--help"},
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
