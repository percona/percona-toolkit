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

package oplog

import (
	"context"
	"sort"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"

	tu "github.com/percona/percona-toolkit/src/go/internal/testutils"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

func TestGetOplogInfo(t *testing.T) {
	testCases := []struct {
		name        string
		port        string
		sets        []string
		viaShardMap bool
	}{
		{
			name:        "from_mongos",
			port:        tu.MongoDBMongosPort,
			sets:        []string{"cnf-serv", "rs1", "rs2"},
			viaShardMap: true,
		},
		{
			name: "from_mongod",
			port: tu.MongoDBShard1PrimaryPort,
			sets: []string{"rs1"},
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()

			client, err := tu.TestClient(ctx, test.port)
			require.NoError(t, err, "cannot get a new MongoDB client")
			defer func() { _ = client.Disconnect(ctx) }()

			raw, err := client.Database("admin").RunCommand(ctx, bson.D{{Key: "isMaster", Value: 1}}).Raw()
			require.NoError(t, err)

			var md proto.MasterDoc
			require.NoError(t, bson.Unmarshal(raw, &md))

			members, err := Discover(ctx, client, md, raw, 5*time.Second)
			require.NoError(t, err)
			require.NotEmpty(t, members)

			self := 0
			for _, m := range members {
				assert.Equal(t, test.viaShardMap, m.ViaShardMap, m.Host)
				if m.Self {
					self++
				}
			}
			assert.Equal(t, map[bool]int{true: 0, false: 1}[test.viaShardMap], self)

			rows, _ := GetOplogInfo(ctx, client, tu.TestClientOptions(test.port), members, 4, 5*time.Second)
			require.Len(t, rows, len(members))

			seen := map[string]bool{}
			for _, r := range rows {
				seen[r.ReplicaSet] = true

				assert.Empty(t, r.Error, r.Hostname)
				assert.True(t, r.HasData(), r.Hostname)
				assert.Contains(t, []string{"PRIMARY", "SECONDARY"}, r.State, r.Hostname)
				assert.NotEmpty(t, r.Primary, r.Hostname)
				assert.Positive(t, r.MaxSizeMB, r.Hostname)
				assert.Positive(t, r.Size, r.Hostname)
				assert.False(t, r.Now.IsZero(), r.Hostname)
				assert.False(t, r.ElectionTime.IsZero(), r.Hostname)
				assert.Equal(t, time.UTC, r.TLast.Location(), r.Hostname)
				assert.False(t, r.TFirst.After(r.TLast), r.Hostname)
				assert.NotEmpty(t, r.Running, r.Hostname)

				if r.State == "PRIMARY" {
					assert.Equal(t, r.Hostname, r.Primary)
				}
			}

			var sets []string
			for s := range seen {
				sets = append(sets, s)
			}
			sort.Strings(sets)
			assert.Equal(t, test.sets, sets)
			assert.True(t, sort.IsSorted(proto.OpLogs(rows)))
		})
	}
}
