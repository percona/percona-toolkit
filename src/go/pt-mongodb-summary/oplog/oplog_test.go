package oplog

import (
	"context"
	"fmt"
	"testing"
	"time"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func TestGetOplogCollection(t *testing.T) {
	testCases := []struct {
		name string
		uri  string
		want string
		err  bool
	}{
		{
			name: "from_mongos",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBMongosPort),
			want: "",
			err:  true,
		},
		{
			name: "from_mongod",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard1PrimaryPort),
			want: "oplog.rs",
			err:  false,
		},
		{
			name: "from_non_sharded",
			uri:  fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard3PrimaryPort),
			want: "oplog.rs",
			err:  false,
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

			oplogCol, err := getOplogCollection(ctx, client)
			if (err != nil) != test.err {
				t.Errorf("Expected error=%v, got %v", test.err, err)
			}
			if oplogCol != test.want {
				t.Errorf("Want oplog collection to be %q, got %q", test.want, oplogCol)
			}
		})
	}
}

func TestGetOplogInfo(t *testing.T) {
	testCases := []struct {
		name     string
		uri      string
		wantHost bool
		err      bool
	}{
		{
			name:     "from_mongos",
			uri:      fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBMongosPort),
			wantHost: false,
			err:      true,
		},
		{
			name:     "from_mongod",
			uri:      fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard1PrimaryPort),
			wantHost: true,
			err:      false,
		},
		{
			name:     "from_non_sharded",
			uri:      fmt.Sprintf("mongodb://%s:%s@%s:%s", tu.MongoDBUser, tu.MongoDBPassword, tu.MongoDBHost, tu.MongoDBShard3PrimaryPort),
			wantHost: true,
			err:      false,
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			clientOptions := options.Client().ApplyURI(test.uri)
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()

			oplogInfo, err := GetOplogInfo(ctx, clientOptions.Hosts, clientOptions)
			if (err != nil) != test.err {
				t.Errorf("Expected error=%v, got %v", test.err, err)
			}
			if test.wantHost && (len(oplogInfo) == 0 || oplogInfo[0].Hostname == "") {
				t.Error("Expected structure with data. Hostname is empty")
			}
		})
	}
}
