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
	"cmp"
	"context"
	"slices"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const mongosPingWindow = 300 * time.Second

type mongosInstance struct {
	Name     string    `bson:"_id"`
	LastPing time.Time `bson:"ping"`
	UpTime   int       `bson:"up"`
	Version  string    `bson:"mongoVersion"`
}

type mongosInfo struct {
	Instances []mongosInstance `bson:"instances"`
}

func (t mongosInfo) MaxNameLen() int {
	width := len("Host")
	for _, m := range t.Instances {
		width = max(width, len(m.Name))
	}

	return width
}

type shardEntry struct {
	ID       string   `bson:"_id"`
	Host     string   `bson:"host"`
	Draining bool     `bson:"draining"`
	Zones    []string `bson:"tags"`
}

func (s shardEntry) State() string {
	if s.Draining {
		return "draining"
	}

	return "active"
}

func (s shardEntry) ZoneList() string {
	if len(s.Zones) == 0 {
		return "-"
	}

	return strings.Join(s.Zones, ",")
}

type shardsInfo struct {
	Shards []shardEntry `bson:"shards"`
}

func (s shardsInfo) IDWidth() int {
	width := len("Shard")
	for _, sh := range s.Shards {
		width = max(width, len(sh.ID))
	}

	return width
}

func (s shardsInfo) ZonesWidth() int {
	width := len("Zones")
	for _, sh := range s.Shards {
		width = max(width, len(sh.ZoneList()))
	}

	return width
}

type shardingSource interface {
	mongos(ctx context.Context, since time.Time) ([]mongosInstance, error)
	listShards(ctx context.Context) (bson.Raw, error)
}

type mongoShardingSource struct {
	client *mongo.Client
}

func findOptions(ctx context.Context) (*options.FindOptions, error) {
	opts := options.Find()
	if deadline, ok := ctx.Deadline(); ok {
		left := time.Until(deadline)
		if left <= 0 {
			return nil, context.DeadlineExceeded
		}

		opts.SetMaxTime(left)
	}

	return opts, nil
}

func (s mongoShardingSource) mongos(ctx context.Context, since time.Time) ([]mongosInstance, error) {
	opts, err := findOptions(ctx)
	if err != nil {
		return nil, err
	}

	filter := bson.M{"ping": bson.M{"$gt": since}}

	cursor, err := s.client.Database("config").Collection("mongos").Find(ctx, filter, opts)
	if err != nil {
		return nil, err
	}

	var instances []mongosInstance
	if err := cursor.All(ctx, &instances); err != nil {
		return nil, err
	}

	return instances, nil
}

func (s mongoShardingSource) listShards(ctx context.Context) (bson.Raw, error) {
	return runRaw(ctx, s.client, "admin", bson.D{{Key: "listShards", Value: 1}})
}

func getShardingInfo(ctx context.Context, client *mongo.Client, snap *snapshot, hi *hostInfo, b *budget, g *gaps) (*mongosInfo, *shardsInfo) {
	return getShardingInfoFrom(ctx, mongoShardingSource{client: client}, snap, hi, b, g)
}

func getShardingInfoFrom(ctx context.Context, src shardingSource, snap *snapshot, hi *hostInfo, b *budget, g *gaps,
) (*mongosInfo, *shardsInfo) {
	isMongos := snap.isMongos()
	if hi.IsArbiter || (!isMongos && snap.clusterRole() != "configsvr") {
		return nil, nil
	}

	now, ok := snap.serverNow()
	if !ok {
		now = time.Now()
	}

	mctx, cancel := b.ctx(ctx, nodeCallTimeout)
	instances, err := src.mongos(mctx, now.Add(-mongosPingWindow))
	cancel()

	var mi *mongosInfo
	if err != nil {
		g.add("Mongos", "Mongos", "find on config.mongos: clusterMonitor", err)
	} else {
		mi = &mongosInfo{Instances: instances}
	}

	if !isMongos {
		return mi, nil
	}

	sctx, cancel := b.ctx(ctx, nodeCallTimeout)
	defer cancel()

	reply, err := src.listShards(sctx)

	var si *shardsInfo
	if err == nil {
		si, err = decodeShards(reply)
	}
	if err != nil {
		g.add("Shards", "Shards", "listShards: clusterMonitor", err)
	}

	return mi, si
}

func decodeShards(reply bson.Raw) (*shardsInfo, error) {
	si := &shardsInfo{}
	if err := bson.Unmarshal(reply, si); err != nil {
		return nil, err
	}

	for i := range si.Shards {
		if si.Shards[i].Zones == nil {
			si.Shards[i].Zones = []string{}
		}
	}

	slices.SortFunc(si.Shards, func(a, b shardEntry) int { return cmp.Compare(a.ID, b.ID) })

	return si, nil
}
