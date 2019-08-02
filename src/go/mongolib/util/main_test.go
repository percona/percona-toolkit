package util

import (
	"context"
	"fmt"
	"reflect"
	"testing"
	"time"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

funci TestGetHostnames(t *testing.T) {
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

			hostnames, err := GetHostnames(ctx, client)
			if err != nil {
				t.Errorf("getHostnames: %v", err)
			}

			if !reflect.DeepEqual(hostnames, test.want) {
				t.Errorf("Invalid hostnames from mongos. Got: %+v, want %+v", hostnames, test.want)
			}
		})
	}
}

func TestGetServerStatus(t *testing.T) {
	client, err := mongo.NewClient(options.Client().ApplyURI("mongodb://admin:admin123456@127.0.0.1:17001"))
	if err != nil {
		t.Fatalf("cannot get a new MongoDB client: %s", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	err = client.Connect(ctx)
	if err != nil {
		t.Fatalf("Cannot connect to MongoDB: %s", err)
	}

	_, err = GetServerStatus(ctx, client)
	if err != nil {
		t.Errorf("getHostnames: %v", err)
	}
}

func TestGetReplicasetMembers(t *testing.T) {
	testCases := []struct {
		name string
		uri  string
		want int
	}{
		{
			name: "from_mongos",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBMongosPort),
			want: 7,
		},
		{
			name: "from_mongod",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard1PrimaryPort),
			want: 3,
		},
		{
			name: "from_non_sharded",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard3PrimaryPort),
			want: 3,
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			clientOptions := options.Client().ApplyURI(test.uri)
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()

			rsm, err := GetReplicasetMembers(ctx, clientOptions)
			if err != nil {
				t.Errorf("Got an error while getting replicaset members: %s", err)
			}
			if len(rsm) != test.want {
				t.Errorf("Invalid number of replicaset members. Want %d, got %d", test.want, len(rsm))
			}
		})
	}
}

func TestGetShardedHosts(t *testing.T) {
	testCases := []struct {
		name string
		uri  string
		want int
		err  bool
	}{
		{
			name: "from_mongos",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBMongosPort),
			want: 2,
			err:  false,
		},
		{
			name: "from_mongod",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard1PrimaryPort),
			want: 0,
			err:  true,
		},
		{
			name: "from_non_sharded",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard3PrimaryPort),
			want: 0,
			err:  true,
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			clientOptions := options.Client().ApplyURI(test.uri)
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()

			client, err := mongo.NewClient(clientOptions)
			if err != nil {
				t.Errorf("Cannot get a new client for host %s: %s", test.uri, err)
			}
			if err := client.Connect(ctx); err != nil {
				t.Errorf("Cannot connect to host %s: %s", test.uri, err)
			}

			rsm, err := GetShardedHosts(ctx, client)
			if (err != nil) != test.err {
				t.Errorf("Invalid error response. Want %v, got %v", test.err, (err != nil))
			}
			if len(rsm) != test.want {
				t.Errorf("Invalid number of replicaset members. Want %d, got %d", test.want, len(rsm))
			}
		})
	}
}
