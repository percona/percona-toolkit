// This program is copyright 2026 Percona LLC and/or its affiliates.
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

package filter

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

func TestFilterByCollection(t *testing.T) {
	tests := []struct {
		name string
		doc  proto.SystemProfile
		want bool
	}{
		{"find", proto.SystemProfile{Ns: "shop.orders", Op: "query"}, false},
		{"other collection", proto.SystemProfile{Ns: "shop.customers", Op: "query"}, true},
		{"update batch", proto.SystemProfile{Ns: "shop.$cmd", Op: "command", Command: bson.D{{Key: "update", Value: "orders"}}}, false},
		{"delete batch", proto.SystemProfile{Ns: "shop.$cmd", Op: "command", Command: bson.D{{Key: "delete", Value: "orders"}}}, false},
		{"batch on other collection", proto.SystemProfile{Ns: "shop.$cmd", Op: "command", Command: bson.D{{Key: "update", Value: "customers"}}}, true},
		{"command without collection", proto.SystemProfile{Ns: "shop.$cmd", Op: "command", Command: bson.D{{Key: "ping", Value: int32(1)}}}, true},
	}

	for _, skip := range []string{"orders", "shop.orders"} {
		f := NewFilterByCollection([]string{skip})
		for _, test := range tests {
			assert.Equal(t, test.want, f(test.doc), "%s (--skip-collections=%s)", test.name, skip)
		}
	}
}
