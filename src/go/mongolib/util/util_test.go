package util

import (
	"context"
	"fmt"
	"testing"
	"time"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/mongo"
)

func TestGetHostnames(t *testing.T) {
	testCases := []struct {
		name      string
		port      string
		want      int
		wantError bool
	}{
		{
			name:      "from_mongos",
			port:      tu.MongoDBMongosPort,
			want:      9,
			wantError: false,
		},
		{
			name:      "from_mongod",
			port:      tu.MongoDBShard1PrimaryPort,
			want:      3,
			wantError: false,
		},
		{
			name:      "from_standalone",
			port:      tu.MongoDBStandalonePort,
			want:      0,
			wantError: true,
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for i, test := range testCases {
		port := test.port
		want := test.want
		wantError := test.wantError

		t.Run(test.name, func(t *testing.T) {
			client, err := tu.TestClient(ctx, port)
			require.NoError(t, err)

			hostnames, err := GetHostnames(ctx, client)
			if err != nil && !wantError {
				t.Errorf("%d) Expecting error=nil, got: %v", i, err)
			}

			require.Equal(t, want, len(hostnames))
		})
	}
}

func TestGetServerStatus(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := tu.TestClient(ctx, tu.MongoDBShard1PrimaryPort)
	require.NoError(t, err)

	_, err = GetServerStatus(ctx, client)
	if err != nil {
		t.Errorf("getHostnames: %v", err)
	}
}

func TestGetReplicasetMembers(t *testing.T) {
	testCases := []struct {
		name    string
		port    string
		want    int
		wantErr bool
	}{
		/* Replication is not enabled in the current sandbox
		{
			name:    "from_mongos",
			port:    tu.MongoDBMongosPort,
			want:    7,
			wantErr: false,
		},
		*/
		{
			name:    "from_mongod",
			port:    tu.MongoDBShard1PrimaryPort,
			want:    3,
			wantErr: false,
		},
		{
			name:    "from_standalone",
			port:    tu.MongoDBStandalonePort,
			want:    0,
			wantErr: true,
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			clientOptions := tu.TestClientOptions(test.port)

			rsm, err := GetReplicasetMembers(ctx, clientOptions)
			if err != nil && !test.wantErr {
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
		port string
		want int
		err  bool
	}{
		{
			name: "from_mongos",
			port: tu.MongoDBMongosPort,
			want: 2,
			err:  false,
		},
		{
			name: "from_mongod",
			port: tu.MongoDBShard1PrimaryPort,
			want: 0,
			err:  true,
		},
		{
			name: "from_non_sharded",
			port: tu.MongoDBShard3PrimaryPort,
			want: 0,
			err:  true,
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			clientOptions := tu.TestClientOptions(test.port)

			client, err := mongo.NewClient(clientOptions)
			if err != nil {
				t.Errorf("Cannot get a new client for host at port %s: %s", test.port, err)
			}

			if err := client.Connect(ctx); err != nil {
				t.Errorf("Cannot connect to host at port %s: %s", test.port, err)
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

func TestReplicasetConfig(t *testing.T) {
	t.Skip("current sandbox doesn't support replicasets")

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	tcs := []struct {
		port             string
		wantID           string
		wantConfigServer bool
		wantError        error
	}{
		{
			port:             tu.MongoDBStandalonePort,
			wantID:           "",
			wantConfigServer: false,
			wantError: mongo.CommandError{
				Code:    76,
				Message: "not running with --replSet",
				Labels:  []string(nil),
				Name:    "NoReplicationEnabled",
			},
		},
		{
			port:             tu.MongoDBMongosPort,
			wantID:           "",
			wantConfigServer: false,
			wantError: mongo.CommandError{
				Code:    59,
				Message: "no such cmd: replSetGetConfig",
				Labels:  []string(nil),
				Name:    "CommandNotFound",
			},
		},
		{
			port:             tu.MongoDBShard1PrimaryPort,
			wantID:           "rs1",
			wantConfigServer: false,
		},
		{
			port:             tu.MongoDBConfigsvr1Port,
			wantID:           "csReplSet",
			wantConfigServer: true,
		},
	}

	for _, tc := range tcs {
		client, err := tu.TestClient(ctx, tc.port)
		assert.NoError(t, err)

		rs, err := ReplicasetConfig(ctx, client)
		assert.Equal(t, tc.wantError, err, fmt.Sprintf("%v", tc.port))

		if tc.wantError != nil {
			continue
		}

		assert.Equal(t, tc.wantID, rs.Config.ID)
		assert.Equal(t, tc.wantConfigServer, rs.Config.ConfigServer)
		assert.NotEmpty(t, rs.Config.Settings.ReplicaSetID.Hex())
	}
}

func TestClusterID(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	tcs := []struct {
		port    string
		emptyID bool
	}{
		{
			port:    tu.MongoDBMongosPort,
			emptyID: false,
		},
		{
			port:    tu.MongoDBShard1PrimaryPort,
			emptyID: false,
		},
		{
			port:    tu.MongoDBShard1Secondary1Port,
			emptyID: false,
		},
		{
			port:    tu.MongoDBConfigsvr1Port,
			emptyID: false,
		},
		{
			port:    tu.MongoDBStandalonePort,
			emptyID: true,
		},
	}

	for _, tc := range tcs {
		client, err := tu.TestClient(ctx, tc.port)
		assert.NoError(t, err)
		cid, err := ClusterID(ctx, client)
		assert.NoError(t, err, fmt.Sprintf("port: %v", tc.port))
		assert.Equal(t, cid == "", tc.emptyID)
	}
}

func TestMyState(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	tcs := []struct {
		port string
		want int
	}{
		{
			port: tu.MongoDBShard1PrimaryPort,
			want: 1,
		},
		{
			port: tu.MongoDBShard1Secondary1Port,
			want: 2,
		},
		{
			port: tu.MongoDBMongosPort,
			want: 0,
		},
		{
			port: tu.MongoDBStandalonePort,
			want: 0,
		},
	}

	for _, tc := range tcs {
		client, err := tu.TestClient(ctx, tc.port)
		assert.NoError(t, err)

		state, err := MyState(ctx, client)
		assert.NoError(t, err)
		assert.Equal(t, tc.want, state, fmt.Sprintf("port: %v", tc.port))
	}
}
