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
	"context"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

const defaultSlowMs = 100

type connectionsInfo struct {
	Current                int64
	Available              int64
	Limit                  int64
	MaxIncomingConnections *int64
	Active                 *int64
	Rejected               *int64
	TotalCreated           int64
	TotalCreatedWrapped    bool
}

type profilingInfo struct {
	SlowMs        int64
	SampleRate    float64
	StartupSlowMs *int64
	AdminFilter   string
}

func buildConnections(snap *snapshot) *connectionsInfo {
	conns, ok := rawDoc(snap.ServerStatus, "connections")
	if !ok {
		return nil
	}

	limit, ok := snap.maxConns()
	if !ok {
		return nil
	}

	optional := func(doc bson.Raw, path ...string) *int64 {
		if v, ok := rawInt64(doc, path...); ok {
			return &v
		}

		return nil
	}

	c := &connectionsInfo{
		Limit:                  limit,
		MaxIncomingConnections: optional(snap.parsed(), "net", "maxIncomingConnections"),
		Active:                 optional(conns, "active"),
		Rejected:               optional(conns, "rejected"),
	}
	c.Current, _ = rawInt64(conns, "current")
	c.Available, _ = rawInt64(conns, "available")
	c.TotalCreated, _ = rawInt64(conns, "totalCreated")

	if c.TotalCreated < 0 {
		c.TotalCreated += 1 << 32
		c.TotalCreatedWrapped = true
	}

	return c
}

func (c *connectionsInfo) LimitSource() string {
	if c.Limit == c.Current+c.Available {
		return "current + available"
	}

	return "current + available + queued for establishment"
}

func getProfiling(ctx context.Context, client *mongo.Client, snap *snapshot, hi *hostInfo, b *budget, g *gaps) *profilingInfo {
	if hi.IsArbiter {
		return nil
	}

	ctx, cancel := b.ctx(ctx, nodeCallTimeout)
	defer cancel()

	reply, err := runRaw(ctx, client, "admin", bson.D{{Key: "profile", Value: -1}})
	if err != nil {
		g.add("Connections & Profiling", "Profiling", "profile: clusterMonitor", err)

		return nil
	}

	return buildProfiling(reply, snap)
}

func buildProfiling(reply bson.Raw, snap *snapshot) *profilingInfo {
	p := &profilingInfo{}
	p.SlowMs, _ = rawInt64(reply, "slowms")
	p.SampleRate, _ = rawFloat(reply, "sampleRate")

	if snap.CmdLineOpts != nil {
		startup, ok := rawInt64(snap.parsed(), "operationProfiling", "slowOpThresholdMs")
		if !ok {
			startup = defaultSlowMs
		}

		p.StartupSlowMs = &startup
	}

	if filter, ok := rawDoc(reply, "filter"); ok {
		if js, err := bson.MarshalExtJSON(filter, false, false); err == nil {
			p.AdminFilter = string(js)
		}
	}

	return p
}

func (p *profilingInfo) StartupDiffers() bool {
	return p.StartupSlowMs != nil && *p.StartupSlowMs != p.SlowMs
}
