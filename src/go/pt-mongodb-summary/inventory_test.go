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
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

var _ inventorySource = mongoInventorySource{}

type fakeInventorySource struct {
	mu      sync.Mutex
	calls   []string
	names   []string
	stats   map[string]bson.Raw
	colls   map[string][]collectionEntry
	indexes map[string][]indexStat
	errs    map[string]error
	block   map[string]bool
}

func (s *fakeInventorySource) call(ctx context.Context, name string) error {
	s.mu.Lock()
	s.calls = append(s.calls, name)
	err, block := s.errs[name], s.block[name]
	s.mu.Unlock()

	if block {
		<-ctx.Done()

		return ctx.Err()
	}

	return err
}

func (s *fakeInventorySource) called() []string {
	s.mu.Lock()
	defer s.mu.Unlock()

	return append([]string(nil), s.calls...)
}

func (s *fakeInventorySource) databaseNames(ctx context.Context, authorizedOnly bool) ([]string, error) {
	if err := s.call(ctx, fmt.Sprintf("listDatabases %v", authorizedOnly)); err != nil {
		return nil, err
	}

	return s.names, nil
}

func (s *fakeInventorySource) dbStats(ctx context.Context, db string) (bson.Raw, error) {
	if err := s.call(ctx, "dbStats "+db); err != nil {
		return nil, err
	}

	return s.stats[db], nil
}

func (s *fakeInventorySource) collections(ctx context.Context, db string) ([]collectionEntry, error) {
	if err := s.call(ctx, "listCollections "+db); err != nil {
		return nil, err
	}

	return s.colls[db], nil
}

func (s *fakeInventorySource) indexStats(ctx context.Context, db, coll string) ([]indexStat, error) {
	if err := s.call(ctx, "indexStats "+db+"."+coll); err != nil {
		return nil, err
	}

	return s.indexes[db+"."+coll], nil
}

func newFakeInventorySource() *fakeInventorySource {
	return &fakeInventorySource{
		stats:   map[string]bson.Raw{},
		colls:   map[string][]collectionEntry{},
		indexes: map[string][]indexStat{},
		errs:    map[string]error{},
		block:   map[string]bool{},
	}
}

func (s *fakeInventorySource) addDB(t *testing.T, name string, size int64, colls map[string][]indexStat) {
	t.Helper()

	s.names = append(s.names, name)
	s.stats[name] = invStats(t, size, size/2)

	names := make([]string, 0, len(colls))
	for coll := range colls {
		names = append(names, coll)
	}
	sort.Strings(names)

	for _, coll := range names {
		s.colls[name] = append(s.colls[name], collectionEntry{Name: coll, Type: "collection"})
		s.indexes[name+"."+coll] = colls[coll]
	}
}

type inventoryGate struct {
	mu       sync.Mutex
	size     int
	inFlight int
	peak     int
	opened   bool
	open     chan struct{}
}

func newInventoryGate(size int) *inventoryGate {
	return &inventoryGate{size: size, open: make(chan struct{})}
}

func (g *inventoryGate) wait(ctx context.Context) error {
	g.mu.Lock()
	g.inFlight++
	g.peak = max(g.peak, g.inFlight)
	if g.inFlight == g.size && !g.opened {
		g.opened = true
		close(g.open)
	}
	g.mu.Unlock()

	defer func() {
		g.mu.Lock()
		g.inFlight--
		g.mu.Unlock()
	}()

	select {
	case <-g.open:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (g *inventoryGate) maxInFlight() int {
	g.mu.Lock()
	defer g.mu.Unlock()

	return g.peak
}

type gatedInventorySource struct {
	*fakeInventorySource
	pass, walk *inventoryGate
}

func (s *gatedInventorySource) dbStats(ctx context.Context, db string) (bson.Raw, error) {
	if err := s.pass.wait(ctx); err != nil {
		return nil, err
	}

	return s.fakeInventorySource.dbStats(ctx, db)
}

func (s *gatedInventorySource) indexStats(ctx context.Context, db, coll string) ([]indexStat, error) {
	if err := s.walk.wait(ctx); err != nil {
		return nil, err
	}

	return s.fakeInventorySource.indexStats(ctx, db, coll)
}

func invStats(t *testing.T, storage, index int64) bson.Raw {
	t.Helper()

	return mustRaw(t, bson.D{
		{Key: "collections", Value: int64(5)},
		{Key: "views", Value: int64(1)},
		{Key: "objects", Value: int64(10)},
		{Key: "dataSize", Value: int32(1000)},
		{Key: "storageSize", Value: storage},
		{Key: "indexes", Value: int64(7)},
		{Key: "indexSize", Value: index},
	})
}

func invIndex(t *testing.T, name string, key bson.D, expireAfterSeconds any) indexStat {
	t.Helper()

	spec := bson.D{{Key: "v", Value: int32(2)}, {Key: "key", Value: key}, {Key: "name", Value: name}}
	if expireAfterSeconds != nil {
		spec = append(spec, bson.E{Key: "expireAfterSeconds", Value: expireAfterSeconds})
	}

	return indexStat{Name: name, Spec: mustRaw(t, spec)}
}

func invTTL(t *testing.T, field string) indexStat {
	t.Helper()

	return invIndex(t, field+"_1", bson.D{{Key: field, Value: int32(1)}}, int32(3600))
}

func invPlain(t *testing.T, field string) indexStat {
	t.Helper()

	return invIndex(t, field+"_1", bson.D{{Key: field, Value: int32(1)}}, nil)
}

func invPtr(v int64) *int64 {
	return &v
}

func invNames(inv *dbInventory) []string {
	names := make([]string, 0, len(inv.Databases))
	for _, e := range inv.Databases {
		names = append(names, e.Name)
	}

	return names
}

func invEntry(t *testing.T, inv *dbInventory, name string) dbInventoryEntry {
	t.Helper()

	for _, e := range inv.Databases {
		if e.Name == name {
			return e
		}
	}

	require.Failf(t, "database not in the inventory", "%s", name)

	return dbInventoryEntry{}
}

func invLine(t *testing.T, inv *dbInventory, prefix string) string {
	t.Helper()

	for _, line := range inv.Lines() {
		if strings.HasPrefix(line, "  "+prefix+" ") {
			return line
		}
	}

	require.Failf(t, "no inventory line", "%s", prefix)

	return ""
}

func runInventory(src inventorySource, snap *snapshot, hi *hostInfo, d time.Duration) (*dbInventory, *gaps) {
	g := &gaps{isArbiter: hi.IsArbiter}

	return getDatabaseInventory(context.Background(), src, snap, hi, newBudget(d), g), g
}

func assertSameWidth(t *testing.T, lines []string) {
	t.Helper()

	require.NotEmpty(t, lines)
	for _, line := range lines {
		assert.Equal(t, utf8.RuneCountInString(lines[0]), utf8.RuneCountInString(line), line)
	}
}

func TestInventoryAuthorizedFallback(t *testing.T) {
	denied := mongo.CommandError{
		Code:    13,
		Name:    "Unauthorized",
		Message: "not authorized on admin to execute command { listDatabases: 1, authorizedDatabases: false }",
	}

	src := newFakeInventorySource()
	src.addDB(t, "app", 4096, map[string][]indexStat{"c": {invTTL(t, "ts")}})
	src.errs["listDatabases false"] = denied

	inv, g := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	require.NotNil(t, inv)
	assert.Empty(t, g.list)
	assert.Equal(t, []string{"app"}, invNames(inv))
	assert.Equal(t, []string{"only databases this login has privileges on are listed"}, inv.Notes)
	assert.Equal(t, []string{"listDatabases false", "listDatabases true"}, src.called()[:2])
	assert.Equal(t, invPtr(1), invEntry(t, inv, "app").TTLIndexes)

	src = newFakeInventorySource()
	src.errs["listDatabases false"] = denied
	src.errs["listDatabases true"] = denied

	inv, g = runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	assert.Nil(t, inv)
	assert.Equal(t, []collectError{{
		Section: "Database Inventory",
		Item:    "Database Inventory",
		Code:    13,
		Reason:  "not authorized (needs listDatabases: clusterMonitor)",
	}}, g.list)
	assert.Equal(t, []string{"listDatabases false", "listDatabases true"}, src.called())
}

func TestInventoryBudget(t *testing.T) {
	t.Run("TTL walk cut", func(t *testing.T) {
		src := newFakeInventorySource()
		src.names = append(src.names, "admin")
		src.stats["admin"] = invStats(t, 100, 100)
		src.addDB(t, "big1", 1<<30, map[string][]indexStat{"c": {invTTL(t, "ts")}})
		src.addDB(t, "big2", 1<<29, map[string][]indexStat{"c": {invTTL(t, "ts")}})
		src.addDB(t, "mixed", 1<<25, map[string][]indexStat{"a": {invTTL(t, "ts")}, "b": {invTTL(t, "ts")}})
		src.block["indexStats mixed.b"] = true
		for i := 1; i <= 6; i++ {
			name := fmt.Sprintf("slow%d", i)
			src.addDB(t, name, int64(1<<20-i), map[string][]indexStat{"c": {invTTL(t, "ts")}})
			src.block["indexStats "+name+".c"] = true
		}

		start := time.Now()
		inv, g := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, 50*time.Millisecond)
		assert.Less(t, time.Since(start), time.Second)
		require.NotNil(t, inv)
		assert.Empty(t, g.list)

		assert.Equal(t, invPtr(1), invEntry(t, inv, "big1").TTLIndexes)
		assert.Equal(t, invPtr(1), invEntry(t, inv, "big2").TTLIndexes)
		for i := 1; i <= 6; i++ {
			e := invEntry(t, inv, fmt.Sprintf("slow%d", i))
			assert.Nil(t, e.TTLIndexes, e.Name)
			assert.NotNil(t, e.Documents, e.Name)
			assert.Contains(t, e.Error, "time budget", e.Name)
			assert.Regexp(t, `^  slow\d +1 +0 +7 +- `, invLine(t, inv, e.Name))
		}

		mixed := invEntry(t, inv, "mixed")
		assert.Equal(t, invPtr(1), mixed.TTLIndexes)
		assert.True(t, mixed.TTLLowerBound)
		assert.Equal(t, "$indexStats: 1 of 2 collections not reached (time budget)", mixed.Error)
		assert.Regexp(t, `^  mixed +2 +0 +7 +1\+ `, invLine(t, inv, "mixed"))

		assert.Equal(t, []string{"TTL counted for 2 of 9 databases (time budget)"}, inv.Notes)
		assert.Regexp(t, `^  Total \(9\) +10 +0 +63 +3\+ `, invLine(t, inv, "Total"))
		assertSameWidth(t, inv.Lines())
	})

	t.Run("database pass cut", func(t *testing.T) {
		src := newFakeInventorySource()
		src.names = append(src.names, "admin")
		src.stats["admin"] = invStats(t, 100, 100)
		src.addDB(t, "fast1", 1<<30, map[string][]indexStat{"c": {invTTL(t, "ts")}})
		src.addDB(t, "fast2", 1<<29, map[string][]indexStat{"c": {invTTL(t, "ts")}})
		for i := 1; i <= 6; i++ {
			name := fmt.Sprintf("slow%d", i)
			src.addDB(t, name, 1<<20, map[string][]indexStat{"c": {invTTL(t, "ts")}})
			src.block["dbStats "+name] = true
		}

		start := time.Now()
		inv, g := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, 50*time.Millisecond)
		assert.Less(t, time.Since(start), time.Second)
		require.NotNil(t, inv)
		assert.Empty(t, g.list)

		assert.Equal(t, []string{"fast1", "fast2"}, invNames(inv)[:2])
		assert.Equal(t, "admin", invNames(inv)[len(inv.Databases)-1])
		assert.Equal(t, invPtr(1<<30), invEntry(t, inv, "fast1").StorageSize)
		assert.NotNil(t, invEntry(t, inv, "admin").Documents)

		for i := 1; i <= 6; i++ {
			e := invEntry(t, inv, fmt.Sprintf("slow%d", i))
			assert.Nil(t, e.Documents, e.Name)
			assert.Nil(t, e.TTLIndexes, e.Name)
			assert.Contains(t, e.Error, "time budget", e.Name)
			assert.Regexp(t, `^  slow\d( +-){8}$`, invLine(t, inv, e.Name))
		}

		assert.Equal(t, []string{
			"statistics incomplete for 6 of 9 databases (time budget)",
			"TTL counted for 0 of 8 databases (time budget)",
		}, inv.Notes)

		total := invLine(t, inv, "Total")
		assert.True(t, strings.HasSuffix(total, "+"), total)
		assert.Regexp(t, `^  Total \(8\) +2\+ +0\+ +14\+ +- +20\+ `, total)
		assertSameWidth(t, inv.Lines())

		for _, c := range src.called() {
			assert.False(t, strings.HasPrefix(c, "indexStats"), c)
		}
	})
}

func TestInventoryWorkers(t *testing.T) {
	src := &gatedInventorySource{
		fakeInventorySource: newFakeInventorySource(),
		pass:                newInventoryGate(collectWorkers),
		walk:                newInventoryGate(collectWorkers),
	}
	for i := 1; i <= 2*collectWorkers; i++ {
		src.addDB(t, fmt.Sprintf("db%d", i), int64(i)<<20, map[string][]indexStat{"c": {invTTL(t, "ts")}})
	}

	inv, g := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, 2*time.Second)
	require.NotNil(t, inv)
	assert.Empty(t, g.list)
	assert.Empty(t, inv.Notes)

	assert.Equal(t, collectWorkers, src.pass.maxInFlight(), "dbStats calls in flight")
	assert.Equal(t, collectWorkers, src.walk.maxInFlight(), "$indexStats calls in flight")

	require.Len(t, inv.Databases, 2*collectWorkers)
	for _, e := range inv.Databases {
		assert.Empty(t, e.Error, e.Name)
		assert.Equal(t, invPtr(1), e.TTLIndexes, e.Name)
	}
}

func TestInventoryPerCollectionError(t *testing.T) {
	denied := mongo.CommandError{
		Code:    13,
		Name:    "Unauthorized",
		Message: "not authorized on app to execute command { aggregate: \"c3\", pipeline: [ { $indexStats: {} } ] }",
	}
	view := mongo.CommandError{Code: 40602, Name: "Location40602", Message: "$indexStats is only valid as the first stage in a pipeline"}

	src := newFakeInventorySource()
	src.addDB(t, "app", 1<<30, map[string][]indexStat{
		"c1": {invIndex(t, "_id_", bson.D{{Key: "_id", Value: int32(1)}}, nil), invTTL(t, "a"), invPlain(t, "b")},
		"c2": {invTTL(t, "x"), invTTL(t, "y")},
		"c3": nil,
	})
	src.addDB(t, "other", 1<<20, map[string][]indexStat{"d1": nil, "d2": nil})
	src.errs["indexStats app.c3"] = denied
	src.errs["indexStats other.d1"] = denied
	src.errs["indexStats other.d2"] = view

	inv, g := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	require.NotNil(t, inv)
	assert.Empty(t, g.list)

	app := invEntry(t, inv, "app")
	assert.Equal(t, invPtr(3), app.TTLIndexes)
	assert.True(t, app.TTLLowerBound)
	assert.Equal(t, invPtr(7), app.Indexes)
	assert.Equal(t, "$indexStats: failed on 1 of 3 collections", app.Error)
	assert.Regexp(t, `^  app +3 +0 +7 +3\+ `, invLine(t, inv, "app"))

	other := invEntry(t, inv, "other")
	assert.Nil(t, other.TTLIndexes)
	assert.Regexp(t, `^  other +2 +0 +7 +- `, invLine(t, inv, "other"))

	assert.Equal(t, []string{
		"$indexStats failed on app.c3, other.d1: not authorized (needs indexStats: clusterMonitor)",
		"$indexStats failed on other.d2: (Location40602) $indexStats is only valid as the first stage in a pipeline",
	}, inv.Notes)
	assert.Regexp(t, `^  Total \(2\) +5 +0 +14 +3\+ `, invLine(t, inv, "Total"))

	mongos, _ := runInventory(src, &snapshot{}, &hostInfo{NodeType: typeMongos}, time.Minute)
	require.NotNil(t, mongos)
	app = invEntry(t, mongos, "app")
	assert.Equal(t, invPtr(5), app.Indexes)
	assert.Regexp(t, `^  app +3 +0 +5\+ +3\+ `, invLine(t, mongos, "app"))
	assert.Nil(t, invEntry(t, mongos, "other").Indexes)
}

func TestInventoryDatabaseErrors(t *testing.T) {
	hook := logtest.NewGlobal()
	defer hook.Reset()

	denied := mongo.CommandError{Code: 13, Name: "Unauthorized", Message: "not authorized on secret to execute command { dbStats: 1 }"}

	src := newFakeInventorySource()
	src.addDB(t, "app", 1<<30, map[string][]indexStat{"c": {invTTL(t, "ts")}})
	src.addDB(t, "secret", 1<<20, map[string][]indexStat{"c": {invTTL(t, "ts")}})
	src.addDB(t, "hidden", 1<<10, map[string][]indexStat{"c": {invTTL(t, "ts")}})
	src.errs["dbStats secret"] = denied
	src.errs["listCollections hidden"] = errors.New("connection reset by peer")

	inv, g := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	require.NotNil(t, inv)
	assert.Empty(t, g.list)

	assert.Equal(t, []string{"app", "hidden", "secret"}, invNames(inv))

	secret := invEntry(t, inv, "secret")
	assert.Nil(t, secret.Documents)
	assert.Nil(t, secret.Indexes)
	assert.Equal(t, invPtr(1), secret.Collections)
	assert.Equal(t, invPtr(1), secret.TTLIndexes)
	assert.Equal(t, "dbStats: not authorized (needs dbStats: clusterMonitor)", secret.Error)

	hidden := invEntry(t, inv, "hidden")
	assert.Nil(t, hidden.Collections)
	assert.Nil(t, hidden.TTLIndexes)
	assert.NotNil(t, hidden.Documents)
	assert.Equal(t, "listCollections: connection reset by peer", hidden.Error)
	assert.NotContains(t, src.called(), "indexStats hidden.c")

	assert.Equal(t, []string{
		"dbStats failed on secret: not authorized (needs dbStats: clusterMonitor)",
		"listCollections failed on hidden: connection reset by peer",
	}, inv.Notes)
	assert.Regexp(t, `^  Total \(3\) +2\+ +0\+ +14\+ +2\+ +20\+ `, invLine(t, inv, "Total"))

	var warnings []string
	for _, e := range hook.AllEntries() {
		if e.Level == log.WarnLevel {
			warnings = append(warnings, e.Message)
		}
	}
	assert.Len(t, warnings, 2)
}

func TestInventoryNoSpec(t *testing.T) {
	src := newFakeInventorySource()
	src.addDB(t, "app", 1<<20, map[string][]indexStat{"c": {{Name: "_id_"}, {Name: "ts_1"}}})

	inv, _ := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	require.NotNil(t, inv)

	app := invEntry(t, inv, "app")
	assert.Nil(t, app.TTLIndexes)
	assert.False(t, app.TTLLowerBound)
	assert.Contains(t, app.Error, "no index spec")
	assert.Equal(t, []string{"TTL not counted on app: $indexStats returns no index spec (MongoDB 4.2.0 to 4.2.3)"}, inv.Notes)
	assert.Regexp(t, `^  app +1 +0 +7 +- `, invLine(t, inv, "app"))

	mongos, _ := runInventory(src, &snapshot{}, &hostInfo{NodeType: typeMongos}, time.Minute)
	require.NotNil(t, mongos)
	assert.Equal(t, invPtr(2), invEntry(t, mongos, "app").Indexes)

	src.colls["app"] = append(src.colls["app"], collectionEntry{Name: "broken", Type: "collection"})
	src.errs["indexStats app.broken"] = mongo.CommandError{Code: 13, Name: "Unauthorized"}

	mongos, _ = runInventory(src, &snapshot{}, &hostInfo{NodeType: typeMongos}, time.Minute)
	require.NotNil(t, mongos)
	app = invEntry(t, mongos, "app")
	assert.Equal(t, invPtr(2), app.Indexes)
	assert.Nil(t, app.TTLIndexes)
	assert.True(t, app.TTLLowerBound)
	assert.Regexp(t, `^  app +2 +0 +2\+ +- `, invLine(t, mongos, "app"))
}

func TestInventoryNoUserDatabases(t *testing.T) {
	src := newFakeInventorySource()
	for _, name := range []string{"admin", "config", "local"} {
		src.names = append(src.names, name)
		src.stats[name] = invStats(t, 4096, 4096)
	}

	inv, _ := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	require.NotNil(t, inv)
	assert.Equal(t, []string{"admin", "config", "local"}, invNames(inv))
	assert.Equal(t, []string{"no user databases"}, inv.Notes)
	assert.NotContains(t, strings.Join(inv.Lines(), "\n"), "Total")

	mongos, _ := runInventory(src, &snapshot{}, &hostInfo{NodeType: typeMongos}, time.Minute)
	require.NotNil(t, mongos)
	assert.Empty(t, mongos.Databases)
	assert.Len(t, mongos.Lines(), 1)
	assert.Contains(t, mongos.Notes, "no user databases")
}

func TestIsTTLSpec(t *testing.T) {
	single := bson.D{{Key: "ts", Value: int32(1)}}
	spec := func(key bson.D, extra ...bson.E) bson.Raw {
		d := bson.D{{Key: "v", Value: int32(2)}, {Key: "key", Value: key}, {Key: "name", Value: "x"}}

		return mustRaw(t, append(d, extra...))
	}

	tests := []struct {
		name  string
		spec  bson.Raw
		ttl   bool
		known bool
	}{
		{"int32", spec(single, bson.E{Key: "expireAfterSeconds", Value: int32(60)}), true, true},
		{"int64", spec(single, bson.E{Key: "expireAfterSeconds", Value: int64(60)}), true, true},
		{"double", spec(single, bson.E{Key: "expireAfterSeconds", Value: 3600.0}), true, true},
		{"zero", spec(single, bson.E{Key: "expireAfterSeconds", Value: int32(0)}), true, true},
		{"descending", spec(bson.D{{Key: "ts", Value: int32(-1)}}, bson.E{Key: "expireAfterSeconds", Value: int32(1)}), true, true},
		{"compound", spec(bson.D{{Key: "a", Value: int32(1)}, {Key: "ts", Value: int32(1)}},
			bson.E{Key: "expireAfterSeconds", Value: int32(60)}), false, true},
		{"_id", spec(bson.D{{Key: "_id", Value: int32(1)}}, bson.E{Key: "expireAfterSeconds", Value: int32(60)}), false, true},
		{"no expireAfterSeconds", spec(single), false, true},
		{"string expireAfterSeconds", spec(single, bson.E{Key: "expireAfterSeconds", Value: "60"}), false, true},
		{"no key", mustRaw(t, bson.D{{Key: "name", Value: "x"}, {Key: "expireAfterSeconds", Value: int32(60)}}), false, false},
		{"nil spec", nil, false, false},
		{"empty spec", bson.Raw{}, false, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ttl, known := isTTLSpec(tt.spec)
			assert.Equal(t, tt.ttl, ttl)
			assert.Equal(t, tt.known, known)
		})
	}
}

func TestInventoryLongName(t *testing.T) {
	long := strings.Repeat("d", 63)

	src := newFakeInventorySource()
	src.addDB(t, long, 1<<30, map[string][]indexStat{"c": {invTTL(t, "ts")}, "broken": nil})
	src.addDB(t, "short", 1<<20, map[string][]indexStat{"c": {invTTL(t, "ts")}})
	src.names = append(src.names, "admin")
	src.stats["admin"] = invStats(t, 4096, 4096)
	src.errs["indexStats "+long+".broken"] = mongo.CommandError{Code: 13, Name: "Unauthorized"}

	inv, _ := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	require.NotNil(t, inv)

	lines := inv.Lines()
	assertSameWidth(t, lines)
	assert.Len(t, lines, 5)

	cut := strings.Repeat("d", 31) + "…"
	assert.True(t, strings.HasPrefix(lines[1], "  "+cut+"  "), lines[1])
	assert.Equal(t, 32, utf8.RuneCountInString(cut))
	assert.NotContains(t, strings.Join(lines, "\n"), strings.Repeat("d", 32))

	require.Len(t, inv.Notes, 1)
	assert.Contains(t, inv.Notes[0], strings.Repeat("d", 63)[:63]+"…")
	assert.NotContains(t, inv.Notes[0], long+".broken")

	out, err := json.Marshal(inv)
	require.NoError(t, err)
	assert.Contains(t, string(out), `"Name":"`+long+`"`)

	ctrl := newFakeInventorySource()
	ctrl.addDB(t, "bad\nname", 1<<20, map[string][]indexStat{"c": nil})
	inv, _ = runInventory(ctrl, &snapshot{}, &hostInfo{NodeType: "replset"}, time.Minute)
	require.NotNil(t, inv)
	for _, line := range inv.Lines() {
		assert.NotContains(t, line, "\n")
	}
	assert.Contains(t, invLine(t, inv, `"bad\nname"`), `"bad\nname"`)
}

func TestInventoryCount(t *testing.T) {
	doc := mustRaw(t, bson.D{
		{Key: "i32", Value: int32(7)},
		{Key: "i64", Value: int64(1) << 40},
		{Key: "double", Value: 1.5e10},
		{Key: "fraction", Value: 7.6},
		{Key: "nan", Value: math.NaN()},
		{Key: "string", Value: "7"},
	})

	assert.Equal(t, invPtr(7), inventoryCount(doc, "i32"))
	assert.Equal(t, invPtr(1<<40), inventoryCount(doc, "i64"))
	assert.Equal(t, invPtr(15000000000), inventoryCount(doc, "double"))
	assert.Equal(t, invPtr(8), inventoryCount(doc, "fraction"))
	assert.Nil(t, inventoryCount(doc, "nan"))
	assert.Nil(t, inventoryCount(doc, "string"))
	assert.Nil(t, inventoryCount(doc, "missing"))
	assert.Nil(t, inventoryCount(nil, "i32"))
}

func TestInventoryUnreachable(t *testing.T) {
	client, _ := unreachableClient(t, closedAddr(t), 5*time.Second)
	src := mongoInventorySource{client: client}

	start := time.Now()
	inv, g := runInventory(src, &snapshot{}, &hostInfo{NodeType: "replset"}, 300*time.Millisecond)
	assert.Less(t, time.Since(start), 2*time.Second)
	assert.Nil(t, inv)
	require.Len(t, g.list, 1)
	assert.Equal(t, "Database Inventory", g.list[0].Section)
	assert.Equal(t, "timed out", g.list[0].Reason)

	expired, cancel := context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
	defer cancel()

	start = time.Now()
	_, err := src.indexStats(expired, "app", "c")
	assert.ErrorIs(t, err, context.DeadlineExceeded)
	_, err = src.dbStats(expired, "app")
	assert.Error(t, err)
	_, err = src.collections(expired, "app")
	assert.Error(t, err)
	_, err = src.databaseNames(expired, true)
	assert.Error(t, err)
	assert.Less(t, time.Since(start), time.Second)

	short, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	_, err = src.indexStats(short, "app", "c")
	require.Error(t, err)
	assert.True(t, inventoryTimedOut(short, err), err.Error())
}
