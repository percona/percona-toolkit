package oplog

import (
	"context"
	"testing"
	"time"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
)

func TestGetOplogCollection(t *testing.T) {
	testCases := []struct {
		name string
		port string
		want string
		err  bool
	}{
		{
			name: "from_mongos",
			port: tu.MongoDBMongosPort,
			want: "",
			err:  true,
		},
		{
			name: "from_mongod",
			port: tu.MongoDBShard1PrimaryPort,
			want: "oplog.rs",
			err:  false,
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
		port     string
		wantHost bool
		err      bool
	}{
		{
			name:     "from_mongos",
			port:     tu.MongoDBMongosPort,
			wantHost: false,
			err:      true,
		},
		{
			name:     "from_mongod",
			port:     tu.MongoDBShard1PrimaryPort,
			wantHost: true,
			err:      false,
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			oplogInfo, err := GetOplogInfo(ctx, []string{"127.0.0.1:" + test.port}, tu.TestClientOptions(test.port))
			if (err != nil) != test.err {
				t.Errorf("Expected error=%v, got %v", test.err, err)
			}
			if test.wantHost && (len(oplogInfo) == 0 || oplogInfo[0].Hostname == "") {
				t.Error("Expected structure with data. Hostname is empty")
			}
		})
	}
}
