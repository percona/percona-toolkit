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
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const (
	inventorySection      = "Database Inventory"
	inventoryScopeNode    = "node"
	inventoryScopeCluster = "cluster"
	inventoryNameWidth    = 32
	inventoryTargetWidth  = 64
	inventoryNoteTargets  = 3
	inventoryBudgetReason = "not reached (time budget)"
	inventoryRowFormat    = "  %-*s  %*s  %*s  %*s  %*s  %*s  %*s  %*s  %*s"

	inventoryMongosNote     = "via mongos: sizes and documents are summed over shards and may include orphans pending cleanup"
	inventoryShardNote      = "connect through mongos for per-database statistics"
	inventoryAuthorizedNote = "only databases this login has privileges on are listed"
	inventoryNoUserDBsNote  = "no user databases"
)

var (
	inventoryInternalDBs = map[string]bool{"admin": true, "config": true, "local": true}
	inventoryHeader      = []string{"Database", "Colls", "Views", "Indexes", "TTL Idx", "Documents", "Data", "Storage", "Idx Size"}
)

type inventorySource interface {
	databaseNames(ctx context.Context, authorizedOnly bool) ([]string, error)
	dbStats(ctx context.Context, db string) (bson.Raw, error)
	collections(ctx context.Context, db string) ([]collectionEntry, error)
	indexStats(ctx context.Context, db, coll string) ([]indexStat, error)
}

type mongoInventorySource struct {
	client *mongo.Client
}

type collectionEntry struct {
	Name string
	Type string
}

type indexStat struct {
	Name string
	Spec bson.Raw
}

type dbInventoryEntry struct {
	Name          string
	Internal      bool
	Collections   *int64
	Views         *int64
	Indexes       *int64
	TTLIndexes    *int64
	TTLLowerBound bool
	Documents     *int64
	DataSize      *int64
	StorageSize   *int64
	IndexSize     *int64
	Error         string
}

type dbInventory struct {
	Scope     string
	Databases []dbInventoryEntry
	Notes     []string
}

type inventoryDB struct {
	entry       dbInventoryEntry
	statsMissed bool
	statsErr    error
	collsMissed bool
	collsErr    error
	listed      bool
	walk        []string
	walkOK      int
	walkMissed  int
	walkFailed  int
	indexes     int64
	ttl         int64
	noSpec      bool
}

type inventoryWalkJob struct {
	db    *inventoryDB
	coll  string
	stats []indexStat
	err   error
	done  bool
}

type inventoryFailure struct {
	command string
	target  string
	err     error
}

type inventoryRun struct {
	src      inventorySource
	mongos   bool
	dbs      []*inventoryDB
	failures []inventoryFailure
}

func (s mongoInventorySource) databaseNames(ctx context.Context, authorizedOnly bool) ([]string, error) {
	return s.client.ListDatabaseNames(ctx, bson.D{}, options.ListDatabases().SetAuthorizedDatabases(authorizedOnly))
}

func (s mongoInventorySource) dbStats(ctx context.Context, db string) (bson.Raw, error) {
	return runRaw(ctx, s.client, db, bson.D{{Key: "dbStats", Value: 1}})
}

func (s mongoInventorySource) collections(ctx context.Context, db string) ([]collectionEntry, error) {
	opts := options.ListCollections().SetNameOnly(true).SetAuthorizedCollections(true)

	cur, err := s.client.Database(db).ListCollections(ctx, bson.D{}, opts)
	if err != nil {
		return nil, err
	}
	defer func() { _ = cur.Close(ctx) }()

	var out []collectionEntry
	for cur.Next(ctx) {
		out = append(out, collectionFromRaw(cur.Current))
	}

	return out, cur.Err()
}

func (s mongoInventorySource) indexStats(ctx context.Context, db, coll string) ([]indexStat, error) {
	opts := options.Aggregate()
	if deadline, ok := ctx.Deadline(); ok {
		left := time.Until(deadline)
		if left <= 0 {
			return nil, context.DeadlineExceeded
		}

		opts.SetMaxTime(left)
	}

	pipeline := mongo.Pipeline{{{Key: "$indexStats", Value: bson.D{}}}}

	cur, err := s.client.Database(db).Collection(coll).Aggregate(ctx, pipeline, opts)
	if err != nil {
		return nil, err
	}
	defer func() { _ = cur.Close(ctx) }()

	var out []indexStat
	for cur.Next(ctx) {
		out = append(out, indexStatFromRaw(cur.Current))
	}

	return out, cur.Err()
}

func collectionFromRaw(doc bson.Raw) collectionEntry {
	name, _ := rawString(doc, "name")

	typ, ok := rawString(doc, "type")
	if !ok {
		typ = "collection"
	}

	return collectionEntry{Name: name, Type: typ}
}

func indexStatFromRaw(doc bson.Raw) indexStat {
	name, _ := rawString(doc, "name")
	spec, _ := rawDoc(doc, "spec")

	return indexStat{Name: name, Spec: append(bson.Raw(nil), spec...)}
}

func isTTLSpec(spec bson.Raw) (bool, bool) {
	key, ok := rawDoc(spec, "key")
	if !ok {
		return false, false
	}

	fields, err := key.Elements()
	if err != nil || len(fields) == 0 {
		return false, false
	}

	expire, ok := rawValue(spec, "expireAfterSeconds")
	if !ok || (expire.Type != bson.TypeInt32 && expire.Type != bson.TypeInt64 && expire.Type != bson.TypeDouble) {
		return false, true
	}

	return len(fields) == 1 && fields[0].Key() != "_id", true
}

func getDatabaseInventory(ctx context.Context, src inventorySource, snap *snapshot, hi *hostInfo, b *budget, g *gaps) *dbInventory {
	if hi == nil || hi.IsArbiter {
		return nil
	}

	names, authorizedOnly, err := inventoryDatabaseNames(ctx, src, b)
	if err != nil {
		g.add(inventorySection, inventorySection, "listDatabases: clusterMonitor", err)

		return nil
	}

	r := &inventoryRun{src: src, mongos: hi.NodeType == typeMongos || (snap != nil && snap.isMongos())}
	inv := &dbInventory{Scope: inventoryScopeNode}
	skipUser := false

	switch {
	case r.mongos:
		inv.Scope = inventoryScopeCluster
		inv.Notes = append(inv.Notes, inventoryMongosNote)
	case hi.ClusterRole != "" || (snap != nil && snap.clusterRole() != ""):
		skipUser = true
		inv.Notes = append(inv.Notes, inventoryShardNote)
	}

	if authorizedOnly {
		inv.Notes = append(inv.Notes, inventoryAuthorizedNote)
	}

	r.plan(names, skipUser)

	pctx, cancel := b.ctx(ctx, dbPassBudget)
	eachParallel(collectWorkers, len(r.dbs), func(i int) { r.readDatabase(pctx, r.dbs[i]) })
	cancel()

	r.sortDatabases()

	wctx, cancel := b.ctx(ctx, ttlWalkBudget)
	r.walkIndexes(wctx)
	cancel()

	inv.Databases = make([]dbInventoryEntry, 0, len(r.dbs))
	for _, db := range r.dbs {
		inv.Databases = append(inv.Databases, db.finish(r.mongos))
	}

	inv.Notes = append(inv.Notes, r.notes(skipUser)...)

	return inv
}

func inventoryDatabaseNames(ctx context.Context, src inventorySource, b *budget) ([]string, bool, error) {
	lctx, cancel := b.ctx(ctx, nodeCallTimeout)
	names, err := src.databaseNames(lctx, false)
	cancel()

	if err == nil || errorCode(err) != codeUnauthorized {
		return names, false, err
	}

	log.Infof("cannot list all databases, listing the authorized ones: %s", err)

	lctx, cancel = b.ctx(ctx, nodeCallTimeout)
	defer cancel()

	names, err = src.databaseNames(lctx, true)

	return names, true, err
}

func (r *inventoryRun) plan(names []string, skipUser bool) {
	var users []*inventoryDB

	for _, name := range names {
		internal := inventoryInternalDBs[name]

		switch {
		case internal && r.mongos, !internal && skipUser:
			continue
		case internal:
			r.dbs = append(r.dbs, &inventoryDB{entry: dbInventoryEntry{Name: name, Internal: true}})
		default:
			users = append(users, &inventoryDB{entry: dbInventoryEntry{Name: name}})
		}
	}

	r.dbs = append(r.dbs, users...)
}

func (r *inventoryRun) readDatabase(ctx context.Context, db *inventoryDB) {
	user := !db.entry.Internal

	if ctx.Err() != nil {
		db.statsMissed, db.collsMissed = true, user

		return
	}

	stats, err := r.src.dbStats(ctx, db.entry.Name)
	switch {
	case inventoryTimedOut(ctx, err):
		db.statsMissed = true
	case err != nil:
		db.statsErr = err
	default:
		db.setStats(stats, r.mongos)
	}

	if !user {
		return
	}

	if ctx.Err() != nil {
		db.collsMissed = true

		return
	}

	colls, err := r.src.collections(ctx, db.entry.Name)
	switch {
	case inventoryTimedOut(ctx, err):
		db.collsMissed = true
	case err != nil:
		db.collsErr = err
	default:
		db.setCollections(colls)
	}
}

func (db *inventoryDB) setStats(stats bson.Raw, mongos bool) {
	e := &db.entry
	e.Documents = inventoryCount(stats, "objects")
	e.DataSize = inventoryCount(stats, "dataSize")
	e.StorageSize = inventoryCount(stats, "storageSize")
	e.IndexSize = inventoryCount(stats, "indexSize")

	if !mongos {
		e.Indexes = inventoryCount(stats, "indexes")
	}

	if e.Internal {
		e.Collections = inventoryCount(stats, "collections")
		e.Views = inventoryCount(stats, "views")
	}
}

func (db *inventoryDB) setCollections(colls []collectionEntry) {
	var collections, views int64

	for _, c := range colls {
		if c.Type == "view" {
			views++

			continue
		}

		if (c.Type == "collection" || c.Type == "timeseries") && !strings.HasPrefix(c.Name, "system.") {
			collections++
			db.walk = append(db.walk, c.Name)
		}
	}

	db.entry.Collections, db.entry.Views = &collections, &views
	db.listed = true
}

func (db *inventoryDB) size() (int64, bool) {
	if db.entry.StorageSize == nil || db.entry.IndexSize == nil {
		return 0, false
	}

	return *db.entry.StorageSize + *db.entry.IndexSize, true
}

func (r *inventoryRun) sortDatabases() {
	sort.SliceStable(r.dbs, func(i, j int) bool {
		x, y := r.dbs[i], r.dbs[j]
		if x.entry.Internal != y.entry.Internal {
			return y.entry.Internal
		}

		xs, xok := x.size()
		ys, yok := y.size()

		switch {
		case x.entry.Internal || (xok == yok && xs == ys):
			return x.entry.Name < y.entry.Name
		case xok != yok:
			return xok
		}

		return xs > ys
	})
}

func (r *inventoryRun) walkIndexes(ctx context.Context) {
	var jobs []*inventoryWalkJob

	for _, db := range r.dbs {
		for _, coll := range db.walk {
			jobs = append(jobs, &inventoryWalkJob{db: db, coll: coll})
		}
	}

	eachParallel(collectWorkers, len(jobs), func(i int) {
		j := jobs[i]
		if ctx.Err() != nil {
			return
		}

		j.stats, j.err = r.src.indexStats(ctx, j.db.entry.Name, j.coll)
		j.done = !inventoryTimedOut(ctx, j.err)
	})

	for _, j := range jobs {
		switch {
		case !j.done:
			j.db.walkMissed++
		case j.err != nil:
			j.db.walkFailed++
			r.failures = append(r.failures,
				inventoryFailure{command: "$indexStats", target: j.db.entry.Name + "." + j.coll, err: j.err})
		default:
			j.db.walkOK++
			j.db.countIndexes(j.stats)
		}
	}
}

func (db *inventoryDB) countIndexes(stats []indexStat) {
	known, ttl := map[string]bool{}, map[string]bool{}

	for _, s := range stats {
		isTTL, isKnown := isTTLSpec(s.Spec)
		known[s.Name] = known[s.Name] || isKnown
		ttl[s.Name] = ttl[s.Name] || isTTL
	}

	for name, ok := range known {
		switch {
		case !ok:
			db.noSpec = true
		case ttl[name]:
			db.ttl++
		}
	}

	db.indexes += int64(len(known))
}

func (db *inventoryDB) finish(mongos bool) dbInventoryEntry {
	e := db.entry

	var problems []string

	failed := func(command string, missed bool, err error) {
		switch {
		case missed:
			problems = append(problems, command+": "+inventoryBudgetReason)
		case err != nil:
			problems = append(problems, command+": "+inventoryReason(command, err))
		}
	}

	failed("dbStats", db.statsMissed, db.statsErr)
	failed("listCollections", db.collsMissed, db.collsErr)

	if db.listed {
		total := len(db.walk)

		switch {
		case db.walkMissed == total && total > 0:
			problems = append(problems, "$indexStats: "+inventoryBudgetReason)
		case db.walkMissed > 0:
			problems = append(problems, fmt.Sprintf("$indexStats: %d of %d collections %s", db.walkMissed, total, inventoryBudgetReason))
		}

		if db.walkFailed > 0 {
			problems = append(problems, fmt.Sprintf("$indexStats: failed on %d of %d collections", db.walkFailed, total))
		}

		if db.noSpec {
			problems = append(problems, "$indexStats: no index spec")
		}

		if total == 0 || db.walkOK > 0 {
			indexes, ttl := db.indexes, db.ttl
			e.TTLLowerBound = db.walkMissed > 0 || db.walkFailed > 0

			if mongos {
				e.Indexes = &indexes
			}

			if !db.noSpec {
				e.TTLIndexes = &ttl
			}
		}
	}

	e.Error = strings.Join(problems, "; ")

	return e
}

func (r *inventoryRun) notes(skipUser bool) []string {
	var (
		notes                            []string
		noSpec                           []string
		users, passCut, eligible, ttlCut int
	)

	for _, db := range r.dbs {
		if db.statsMissed || db.collsMissed {
			passCut++
		}

		if db.entry.Internal {
			continue
		}

		users++

		if db.noSpec {
			noSpec = append(noSpec, db.entry.Name)
		}

		if db.collsErr == nil {
			eligible++
			if db.collsMissed || db.walkMissed > 0 {
				ttlCut++
			}
		}
	}

	if users == 0 && !skipUser {
		notes = append(notes, inventoryNoUserDBsNote)
	}

	if passCut > 0 {
		logGap(fmt.Sprintf("statistics for %d of %d databases", passCut, len(r.dbs)), "time budget", false)
		notes = append(notes, fmt.Sprintf("statistics incomplete for %d of %d databases (time budget)", passCut, len(r.dbs)))
	}

	if ttlCut > 0 {
		logGap(fmt.Sprintf("TTL index counts for %d of %d databases", ttlCut, eligible), "time budget", false)
		notes = append(notes, fmt.Sprintf("TTL counted for %d of %d databases (time budget)", eligible-ttlCut, eligible))
	}

	if len(noSpec) > 0 {
		notes = append(notes,
			"TTL not counted on "+inventoryTargets(noSpec)+": $indexStats returns no index spec (MongoDB 4.2.0 to 4.2.3)")
	}

	return append(notes, r.failureNotes()...)
}

func (r *inventoryRun) failureNotes() []string {
	var failures []inventoryFailure

	for _, db := range r.dbs {
		if db.statsErr != nil {
			failures = append(failures, inventoryFailure{command: "dbStats", target: db.entry.Name, err: db.statsErr})
		}
	}

	for _, db := range r.dbs {
		if db.collsErr != nil {
			failures = append(failures, inventoryFailure{command: "listCollections", target: db.entry.Name, err: db.collsErr})
		}
	}

	failures = append(failures, r.failures...)

	type group struct {
		command, reason, detail string
		expected                bool
		targets                 []string
	}

	var groups []*group

	byKey := map[string]*group{}

	for _, f := range failures {
		reason, _, expected := classifyError(f.err, false, inventoryNeeds(f.command))
		key := f.command + "\x00" + inventoryCodeName(f.err, reason)

		gr, ok := byKey[key]
		if !ok {
			gr = &group{command: f.command, reason: reason, detail: f.err.Error(), expected: expected}
			byKey[key] = gr
			groups = append(groups, gr)
		}

		gr.targets = append(gr.targets, f.target)
	}

	notes := make([]string, 0, len(groups))
	for _, gr := range groups {
		targets := inventoryTargets(gr.targets)
		logGap(gr.command+" on "+targets, gr.detail, gr.expected)
		notes = append(notes, gr.command+" failed on "+targets+": "+gr.reason)
	}

	return notes
}

func inventoryNeeds(command string) string {
	return strings.TrimPrefix(command, "$") + ": clusterMonitor"
}

func inventoryReason(command string, err error) string {
	reason, _, _ := classifyError(err, false, inventoryNeeds(command))

	return reason
}

func inventoryCodeName(err error, reason string) string {
	var ce mongo.CommandError
	if errors.As(err, &ce) && ce.Name != "" {
		return ce.Name
	}

	return reason
}

func inventoryTargets(targets []string) string {
	shown := targets[:min(len(targets), inventoryNoteTargets)]

	parts := make([]string, 0, len(shown))
	for _, t := range shown {
		parts = append(parts, inventoryCut(t, inventoryTargetWidth))
	}

	s := strings.Join(parts, ", ")
	if rest := len(targets) - len(shown); rest > 0 {
		s += fmt.Sprintf(" and %d more", rest)
	}

	return s
}

func inventoryTimedOut(ctx context.Context, err error) bool {
	return err != nil && (ctx.Err() != nil || mongo.IsTimeout(err))
}

func inventoryCount(doc bson.Raw, key string) *int64 {
	if n, ok := rawInt64(doc, key); ok {
		return &n
	}

	f, ok := rawFloat(doc, key)
	if !ok || math.Abs(f) >= math.MaxInt64 {
		return nil
	}

	n := int64(math.Round(f))

	return &n
}

func inventoryCut(s string, width int) string {
	if strings.ContainsFunc(s, unicode.IsControl) {
		s = strconv.Quote(s)
	}

	if utf8.RuneCountInString(s) <= width {
		return s
	}

	return string([]rune(s)[:width-1]) + "…"
}

func eachParallel(workers, n int, f func(i int)) {
	next := make(chan int)

	var wg sync.WaitGroup

	for w := 0; w < min(workers, n); w++ {
		wg.Add(1)

		go func() {
			defer wg.Done()

			for i := range next {
				f(i)
			}
		}()
	}

	for i := 0; i < n; i++ {
		next <- i
	}

	close(next)
	wg.Wait()
}

type inventorySum struct {
	n       int64
	known   bool
	partial bool
}

func (s *inventorySum) add(v *int64, lowerBound bool) {
	if v == nil {
		s.partial = true

		return
	}

	s.n += *v
	s.known = true
	s.partial = s.partial || lowerBound
}

func (s inventorySum) text(bytes bool) string {
	if !s.known {
		return "-"
	}

	v := strconv.FormatInt(s.n, 10)
	if bytes {
		v = formatBytes(s.n)
	}

	if s.partial {
		v += "+"
	}

	return v
}

type inventoryCells struct {
	colls, views, indexes, ttl, docs, data, storage, indexSize inventorySum
}

func (c *inventoryCells) add(e dbInventoryEntry, cluster bool) {
	c.colls.add(e.Collections, false)
	c.views.add(e.Views, false)
	c.indexes.add(e.Indexes, cluster && e.TTLLowerBound)
	c.ttl.add(e.TTLIndexes, e.TTLLowerBound)
	c.docs.add(e.Documents, false)
	c.data.add(e.DataSize, false)
	c.storage.add(e.StorageSize, false)
	c.indexSize.add(e.IndexSize, false)
}

func (c inventoryCells) row(name string, internal bool) []string {
	ttl := c.ttl.text(false)
	if internal {
		ttl = "n/a"
	}

	return []string{
		name, c.colls.text(false), c.views.text(false), c.indexes.text(false), ttl,
		c.docs.text(false), c.data.text(true), c.storage.text(true), c.indexSize.text(true),
	}
}

func (d *dbInventory) Lines() []string {
	if d == nil {
		return nil
	}

	cluster := d.Scope == inventoryScopeCluster
	rows := [][]string{inventoryHeader}

	var total inventoryCells

	users := 0

	for _, e := range d.Databases {
		if e.Internal {
			continue
		}

		var c inventoryCells
		c.add(e, cluster)
		total.add(e, cluster)
		rows = append(rows, c.row(inventoryCut(e.Name, inventoryNameWidth), false))
		users++
	}

	if users > 0 {
		rows = append(rows, total.row(fmt.Sprintf("Total (%d)", users), false))
	}

	for _, e := range d.Databases {
		if !e.Internal {
			continue
		}

		var c inventoryCells
		c.add(e, cluster)
		rows = append(rows, c.row(inventoryCut(e.Name, inventoryNameWidth), true))
	}

	widths := make([]int, len(inventoryHeader))
	for _, row := range rows {
		for i, cell := range row {
			widths[i] = max(widths[i], utf8.RuneCountInString(cell))
		}
	}

	lines := make([]string, 0, len(rows))
	for _, row := range rows {
		args := make([]any, 0, 2*len(row))
		for i, cell := range row {
			args = append(args, widths[i], cell)
		}

		lines = append(lines, fmt.Sprintf(inventoryRowFormat, args...))
	}

	return lines
}
