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

package proto_test

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
)

func TestMasterDocIsArbiter(t *testing.T) {
	tests := []struct {
		name string
		doc  bson.M
		want bool
	}{
		{
			name: "arbiter_only",
			doc:  bson.M{"setName": "rs0", "arbiterOnly": true, "me": "arb:27017", "arbiters": bson.A{"arb:27017"}},
			want: true,
		},
		{
			name: "me_in_arbiters",
			doc:  bson.M{"setName": "rs0", "me": "arb:27017", "arbiters": bson.A{"arb:27017"}},
			want: true,
		},
		{
			name: "primary",
			doc:  bson.M{"setName": "rs0", "ismaster": true, "me": "m1:27017", "arbiters": bson.A{"arb:27017"}},
			want: false,
		},
		{
			name: "secondary",
			doc:  bson.M{"setName": "rs0", "secondary": true, "me": "m2:27017", "arbiters": bson.A{"arb:27017"}},
			want: false,
		},
		{
			name: "no_me",
			doc:  bson.M{"setName": "rs0", "arbiters": bson.A{"arb:27017"}},
			want: false,
		},
		{
			name: "standalone",
			doc:  bson.M{"ismaster": true},
			want: false,
		},
		{
			name: "mongos",
			doc:  bson.M{"ismaster": true, "msg": "isdbgrid"},
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			raw, err := bson.Marshal(tt.doc)
			require.NoError(t, err)

			var md proto.MasterDoc
			require.NoError(t, bson.Unmarshal(raw, &md))
			assert.Equal(t, tt.want, md.IsArbiter())
		})
	}
}
