/*
   Copyright (c) 2017, Percona LLC and/or its affiliates. All rights reserved.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU Affero General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>
*/

package profiling

import (
	"context"

	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// Enable enabled the mongo profiler
func Enable(ctx context.Context, client *mongo.Client) error {
	res := client.Database("admin").RunCommand(ctx, primitive.M{"profile": 2})
	return res.Err()
}

// Disable disables the mongo profiler
func Disable(ctx context.Context, client *mongo.Client) error {
	res := client.Database("admin").RunCommand(ctx, primitive.M{"profile": 0})
	return res.Err()
}

// Drop drops the system.profile collection for clean up
func Drop(ctx context.Context, client *mongo.Client) error {
	return client.Database("").Collection("system.profile").Drop(ctx)
}
