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
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/x/mongo/driver"
	"go.mongodb.org/mongo-driver/x/mongo/driver/auth"
	"go.mongodb.org/mongo-driver/x/mongo/driver/topology"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
)

const (
	codeUnauthorized         = 13
	codeAuthenticationFailed = 18
	codeNamespaceNotFound    = 26
	codeNoReplicationEnabled = 76
	codeNotYetInitialized    = 94
	codeCollStatsNotFound    = 40280

	statePrimary = 1
	stateArbiter = 7

	noOplogOnArbiter = "no oplog on an arbiter"
	mib              = 1 << 20
)

var (
	errNoCollStats = errors.New("$collStats returned no document")
	errNoTimestamp = errors.New("oplog entry without ts")
)

type Member struct {
	Host        string
	Set         string
	State       string
	Self        bool
	Arbiter     bool
	ViaShardMap bool
	SetRole     string
	Pid         int64
	Engine      proto.StorageEngine
	Priority    *float64
	Votes       *float64
	Hidden      bool
	DelaySecs   int64
	Status      bson.Raw
}

type facts struct {
	peers  []Member
	pid    int64
	engine proto.StorageEngine
	config map[string]Member
}

func Discover(ctx context.Context, client *mongo.Client, md proto.MasterDoc, isMaster bson.Raw,
	timeout time.Duration,
) ([]Member, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	status, err := runCommand(ctx, client, "replSetGetStatus")
	if err == nil {
		return markArbiters(membersFromReplStatus(status), md.Arbiters), nil
	}

	shardMap, smErr := runCommand(ctx, client, "getShardMap")
	if smErr == nil {
		if members := membersFromShardMap(shardMap); len(members) > 0 {
			return members, nil
		}
	}

	code := errorCode(err)
	expected := code == codeNoReplicationEnabled || code == codeNotYetInitialized

	if members := membersFromIsMaster(md, isMaster); len(members) > 0 {
		if expected {
			return members, nil
		}

		return members, err
	}

	switch {
	case expected:
		return nil, nil
	case md.Msg == "isdbgrid" && smErr != nil:
		return nil, smErr
	}

	return nil, err
}

func membersFromReplStatus(doc bson.Raw) []Member {
	set, _ := doc.Lookup("set").StringValueOK()

	var members []Member
	for _, m := range documents(doc, "members") {
		host, _ := m.Lookup("name").StringValueOK()
		if host == "" {
			continue
		}

		state, _ := m.Lookup("stateStr").StringValueOK()
		if health, ok := number(m.Lookup("health")); ok && health == 0 {
			state = "DOWN"
		}

		code, _ := number(m.Lookup("state"))
		self, _ := m.Lookup("self").BooleanOK()

		members = append(members, Member{
			Host:    host,
			Set:     set,
			State:   state,
			Self:    self,
			Arbiter: code == stateArbiter || state == "ARBITER",
			Status:  m,
		})
	}

	sortMembers(members)

	return members
}

func markArbiters(members []Member, arbiters []string) []Member {
	for i := range members {
		if !contains(arbiters, members[i].Host) {
			continue
		}

		members[i].Arbiter = true
		if members[i].State == "DOWN" {
			members[i].State = "ARBITER (down)"
		}
	}

	return members
}

func membersFromShardMap(doc bson.Raw) []Member {
	shards, ok := doc.Lookup("map").DocumentOK()
	if !ok {
		return nil
	}

	if _, err := shards.LookupErr("config"); err != nil {
		return nil
	}

	elems, err := shards.Elements()
	if err != nil {
		return nil
	}

	seen := map[string]bool{}

	var members []Member
	for _, e := range elems {
		value, ok := e.Value().StringValueOK()
		if !ok {
			continue
		}

		set, hosts, found := strings.Cut(value, "/")
		if !found {
			set, hosts = e.Key(), value
		}

		for _, host := range strings.Split(hosts, ",") {
			if host == "" || seen[host] {
				continue
			}

			seen[host] = true
			members = append(members, Member{Host: host, Set: set, SetRole: shardMapRole(e.Key()), ViaShardMap: true})
		}
	}

	sortMembers(members)

	return members
}

func shardMapRole(key string) string {
	if key == "config" {
		return "CONFIGSVR"
	}

	return "SHARDSVR"
}

func membersFromIsMaster(md proto.MasterDoc, raw bson.Raw) []Member {
	set, _ := md.SetName.(string)
	primary, _ := raw.Lookup("primary").StringValueOK()
	secondary, _ := raw.Lookup("secondary").BooleanOK()

	seen := map[string]bool{}

	var members []Member
	add := func(host string, arbiter bool) {
		if host == "" || seen[host] {
			return
		}

		seen[host] = true
		m := Member{Host: host, Set: set, Self: host == md.Me, Arbiter: arbiter}

		switch {
		case arbiter:
			m.State = "ARBITER"
		case host == primary:
			m.State = "PRIMARY"
		case m.Self && secondary:
			m.State = "SECONDARY"
		}

		members = append(members, m)
	}

	for _, key := range []string{"hosts", "passives"} {
		for _, host := range strs(raw, key) {
			add(host, false)
		}
	}

	for _, host := range md.Arbiters {
		add(host, true)
	}

	if set != "" || len(members) > 0 {
		add(md.Me, md.IsArbiter())
	}

	sortMembers(members)

	return members
}

func GetOplogInfo(ctx context.Context, client *mongo.Client, co *options.ClientOptions, members []Member, workers int,
	memberTimeout time.Duration,
) ([]proto.OplogInfo, []Member) {
	r := reader{client: client, co: co}
	w := &walker{read: r.read, timeout: memberTimeout}
	rows := w.walk(ctx, members, workers)

	return rows, w.members(members, rows)
}

type walker struct {
	read    func(ctx context.Context, m Member, row *proto.OplogInfo) (facts, error)
	timeout time.Duration

	mu         sync.Mutex
	authFailed map[string]string
	peers      []Member
	found      map[string]facts
	config     map[string]Member
}

func (w *walker) walk(ctx context.Context, members []Member, workers int) proto.OpLogs {
	rows := w.round(ctx, members, workers)
	if extra := w.unwalked(members); len(extra) > 0 {
		rows = append(rows, w.round(ctx, extra, workers)...)
	}

	sort.Stable(rows)

	return rows
}

func (w *walker) round(ctx context.Context, members []Member, workers int) proto.OpLogs {
	if len(members) == 0 {
		return nil
	}

	rows := make(proto.OpLogs, len(members))
	jobs := make(chan int, len(members))
	gated := map[int][]int{}
	opener := map[string]int{}

	for _, i := range walkOrder(members) {
		m := members[i]
		if m.Self || m.Arbiter {
			jobs <- i

			continue
		}

		if first, ok := opener[m.Set]; ok {
			gated[first] = append(gated[first], i)

			continue
		}

		opener[m.Set] = i
		jobs <- i
	}

	var (
		wg        sync.WaitGroup
		remaining atomic.Int64
	)

	remaining.Store(int64(len(members)))

	for range max(workers, 1) {
		wg.Add(1)

		go func() {
			defer wg.Done()

			for i := range jobs {
				rows[i] = w.member(ctx, members[i])

				for _, j := range gated[i] {
					jobs <- j
				}

				if remaining.Add(-1) == 0 {
					close(jobs)
				}
			}
		}()
	}

	wg.Wait()

	return rows
}

func (w *walker) member(ctx context.Context, m Member) proto.OplogInfo {
	row := proto.OplogInfo{Hostname: m.Host, ReplicaSet: m.Set, State: m.State}

	if m.Arbiter {
		if row.State == "" {
			row.State = "ARBITER"
		}
		row.Error = noOplogOnArbiter

		return row
	}

	if host := w.failedAuth(m.Set); host != "" {
		row.Error = "not tried after authentication failed on " + host

		return row
	}

	if err := ctx.Err(); err != nil {
		row.Error = describeError(err, m.ViaShardMap)
		row.ErrorDetail = err.Error()

		return row
	}

	mctx, cancel := ctx, context.CancelFunc(func() {})
	if w.timeout > 0 {
		mctx, cancel = context.WithTimeout(ctx, w.timeout)
	}
	defer cancel()

	f, err := w.read(mctx, m, &row)
	w.addPeers(m, f.peers)
	w.addFacts(m.Host, f)

	if err != nil {
		log.Infof("cannot read the oplog of %s: %s", m.Host, err)

		row.Error = describeError(err, m.ViaShardMap)
		row.ErrorDetail = err.Error()
		if isAuthError(err) {
			w.setFailedAuth(m.Set, m.Host)
		}
	}

	return row
}

func (w *walker) addPeers(m Member, peers []Member) {
	w.mu.Lock()
	defer w.mu.Unlock()

	for _, p := range peers {
		p.Self = false
		p.ViaShardMap = m.ViaShardMap
		if p.Set == "" {
			p.Set = m.Set
		}
		if p.Set == m.Set {
			p.SetRole = m.SetRole
		}
		w.peers = append(w.peers, p)
	}
}

func (w *walker) addFacts(host string, f facts) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if f.pid != 0 || f.engine.Name != "" {
		if w.found == nil {
			w.found = map[string]facts{}
		}
		w.found[host] = facts{pid: f.pid, engine: f.engine}
	}

	for h, c := range f.config {
		if w.config == nil {
			w.config = map[string]Member{}
		}
		if _, ok := w.config[h]; !ok {
			w.config[h] = c
		}
	}
}

func (w *walker) members(initial []Member, rows []proto.OplogInfo) []Member {
	w.mu.Lock()
	defer w.mu.Unlock()

	known := make(map[string]Member, len(initial)+len(w.peers))
	for _, list := range [][]Member{initial, w.peers} {
		for _, m := range list {
			k, ok := known[m.Host]
			if !ok {
				known[m.Host] = m

				continue
			}

			if len(k.Status) == 0 {
				k.Status = m.Status
			}
			if k.State == "" {
				k.State = m.State
			}
			k.Arbiter = k.Arbiter || m.Arbiter
			known[m.Host] = k
		}
	}

	out := make([]Member, 0, len(rows))
	for _, r := range rows {
		m, ok := known[r.Hostname]
		if !ok {
			m = Member{Host: r.Hostname}
		}

		if m.Set == "" {
			m.Set = r.ReplicaSet
		}
		if r.State != "" {
			m.State = r.State
		}
		if f, ok := w.found[r.Hostname]; ok {
			m.Pid, m.Engine = f.pid, f.engine
		}
		if c, ok := w.config[r.Hostname]; ok {
			m.Priority, m.Votes, m.Hidden, m.DelaySecs = c.Priority, c.Votes, c.Hidden, c.DelaySecs
		}

		out = append(out, m)
	}

	sortMembers(out)

	return out
}

func (w *walker) unwalked(members []Member) []Member {
	w.mu.Lock()
	defer w.mu.Unlock()

	known := make(map[string]bool, len(members))
	for _, m := range members {
		known[m.Host] = true
	}

	var extra []Member
	for _, p := range w.peers {
		if !known[p.Host] {
			known[p.Host] = true
			extra = append(extra, p)
		}
	}

	sortMembers(extra)

	return extra
}

func (w *walker) failedAuth(set string) string {
	w.mu.Lock()
	defer w.mu.Unlock()

	return w.authFailed[set]
}

func (w *walker) setFailedAuth(set, host string) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.authFailed == nil {
		w.authFailed = map[string]string{}
	}

	if _, ok := w.authFailed[set]; !ok {
		w.authFailed[set] = host
	}
}

func walkOrder(members []Member) []int {
	var sets []string

	bySet := map[string][]int{}
	for i, m := range members {
		if _, ok := bySet[m.Set]; !ok {
			sets = append(sets, m.Set)
		}
		bySet[m.Set] = append(bySet[m.Set], i)
	}

	order := make([]int, 0, len(members))
	for round := 0; len(order) < len(members); round++ {
		for _, set := range sets {
			if round < len(bySet[set]) {
				order = append(order, bySet[set][round])
			}
		}
	}

	return order
}

type reader struct {
	client *mongo.Client
	co     *options.ClientOptions
}

func (r reader) read(ctx context.Context, m Member, row *proto.OplogInfo) (facts, error) {
	client := r.client

	var (
		arbiters []string
		f        facts
	)

	if !m.Self || client == nil {
		c, err := util.GetClientForHost(r.co, m.Host)
		if err != nil {
			return f, err
		}

		if err := c.Connect(ctx); err != nil {
			return f, err
		}
		defer func() { _ = c.Disconnect(ctx) }()

		if err := c.Ping(ctx, nil); err != nil {
			return f, err
		}

		hello, stop, err := guard(ctx, c, m, row)
		if stop || err != nil {
			return f, err
		}

		arbiters = strs(hello, "arbiters")
		client = c
		f.pid, f.engine = readProcess(ctx, client, m.Host)
	}

	err := readOplog(ctx, client, row)
	if err != nil && !answered(err) {
		return f, err
	}

	f.peers = markArbiters(readStatus(ctx, client, row), arbiters)
	f.config = readConfig(ctx, client, m.Host)

	return f, err
}

func readProcess(ctx context.Context, client *mongo.Client, host string) (int64, proto.StorageEngine) {
	status, err := runCommand(ctx, client, "serverStatus")
	if err != nil {
		log.Debugf("cannot get serverStatus from %s: %s", host, err)

		return 0, proto.StorageEngine{}
	}

	return processFacts(status)
}

func processFacts(status bson.Raw) (int64, proto.StorageEngine) {
	pid, _ := intValue(status, "pid")

	var engine proto.StorageEngine
	if doc, ok := status.Lookup("storageEngine").DocumentOK(); ok {
		if err := bson.Unmarshal(doc, &engine); err != nil {
			engine = proto.StorageEngine{}
		}
	}

	return pid, engine
}

func readConfig(ctx context.Context, client *mongo.Client, host string) map[string]Member {
	doc, err := runCommand(ctx, client, "replSetGetConfig")
	if err != nil {
		log.Debugf("cannot get replSetGetConfig from %s: %s", host, err)

		return nil
	}

	return parseConfig(doc)
}

func parseConfig(doc bson.Raw) map[string]Member {
	cfg, ok := doc.Lookup("config").DocumentOK()
	if !ok {
		return nil
	}

	out := map[string]Member{}
	for _, d := range documents(cfg, "members") {
		host, _ := d.Lookup("host").StringValueOK()
		if host == "" {
			continue
		}

		m := Member{Host: host}
		if v, ok := number(d.Lookup("priority")); ok {
			m.Priority = &v
		}
		if v, ok := number(d.Lookup("votes")); ok {
			m.Votes = &v
		}
		m.Hidden, _ = d.Lookup("hidden").BooleanOK()

		if v, ok := number(d.Lookup("secondaryDelaySecs")); ok {
			m.DelaySecs = int64(v)
		} else if v, ok := number(d.Lookup("slaveDelay")); ok {
			m.DelaySecs = int64(v)
		}

		out[host] = m
	}

	return out
}

func guard(ctx context.Context, client *mongo.Client, m Member, row *proto.OplogInfo) (bson.Raw, bool, error) {
	hello, err := runCommand(ctx, client, "isMaster")
	if err != nil {
		return nil, true, err
	}

	if arbiter, _ := hello.Lookup("arbiterOnly").BooleanOK(); arbiter {
		row.State = "ARBITER"
		row.Error = noOplogOnArbiter

		return hello, true, nil
	}

	set, _ := hello.Lookup("setName").StringValueOK()
	if set != "" && m.Set != "" && set != m.Set {
		row.Error = fmt.Sprintf("member of replica set %s, not %s", set, m.Set)

		return hello, true, nil
	}

	if row.ReplicaSet == "" {
		row.ReplicaSet = set
	}

	primary, _ := hello.Lookup("ismaster").BooleanOK()
	secondary, _ := hello.Lookup("secondary").BooleanOK()

	switch {
	case primary && set != "":
		row.State = "PRIMARY"
	case secondary:
		row.State = "SECONDARY"
	}

	return hello, false, nil
}

func readOplog(ctx context.Context, client *mongo.Client, row *proto.OplogInfo) error {
	coll := client.Database("local").Collection("oplog.rs")

	stats, err := collStats(ctx, coll)
	if err != nil {
		return err
	}

	row.Size, _ = intValue(stats, "storageStats", "size")
	row.UsedMB = row.Size / mib
	maxSize, _ := intValue(stats, "storageStats", "maxSize")
	row.MaxSizeMB = maxSize / mib

	first, err := entryTime(ctx, coll, 1)
	if err != nil {
		return err
	}

	last, err := entryTime(ctx, coll, -1)
	if err != nil {
		return err
	}

	row.TFirst = first
	row.TLast = last
	row.TimeDiff = last.Sub(first)
	row.TimeDiffHours = row.TimeDiff.Hours()
	row.Running = running(row.TimeDiffHours)

	return nil
}

func collStats(ctx context.Context, coll *mongo.Collection) (bson.Raw, error) {
	pipeline := mongo.Pipeline{
		{{Key: "$collStats", Value: bson.D{{Key: "storageStats", Value: bson.D{}}}}},
		{{Key: "$project", Value: bson.D{{Key: "storageStats.size", Value: 1}, {Key: "storageStats.maxSize", Value: 1}}}},
	}

	opts := options.Aggregate()
	if d, ok := maxTime(ctx); ok {
		opts.SetMaxTime(d)
	}

	cur, err := coll.Aggregate(ctx, pipeline, opts)
	if err != nil {
		return nil, err
	}
	defer func() { _ = cur.Close(ctx) }()

	if !cur.Next(ctx) {
		if err := cur.Err(); err != nil {
			return nil, err
		}

		return nil, errNoCollStats
	}

	return append(bson.Raw(nil), cur.Current...), nil
}

func entryTime(ctx context.Context, coll *mongo.Collection, order int) (time.Time, error) {
	opts := options.FindOne().
		SetSort(bson.D{{Key: "$natural", Value: order}}).
		SetProjection(bson.D{{Key: "ts", Value: 1}})
	if d, ok := maxTime(ctx); ok {
		opts.SetMaxTime(d)
	}

	raw, err := coll.FindOne(ctx, bson.D{}, opts).Raw()
	if err != nil {
		return time.Time{}, err
	}

	t, _, ok := raw.Lookup("ts").TimestampOK()
	if !ok {
		return time.Time{}, errNoTimestamp
	}

	return time.Unix(int64(t), 0).UTC(), nil
}

func readStatus(ctx context.Context, client *mongo.Client, row *proto.OplogInfo) []Member {
	status, err := runCommand(ctx, client, "replSetGetStatus")
	if err != nil {
		log.Debugf("cannot get replSetGetStatus from %s: %s", row.Hostname, err)

		return nil
	}

	if now, ok := status.Lookup("date").TimeOK(); ok {
		row.Now = now.UTC()
	}

	if set, _ := status.Lookup("set").StringValueOK(); row.ReplicaSet == "" {
		row.ReplicaSet = set
	}

	selfPrimary := false

	for _, m := range documents(status, "members") {
		state, _ := number(m.Lookup("state"))

		if self, _ := m.Lookup("self").BooleanOK(); self {
			if s, ok := m.Lookup("stateStr").StringValueOK(); ok {
				row.State = s
			}
			selfPrimary = state == statePrimary
		}

		if state != statePrimary {
			continue
		}

		row.Primary, _ = m.Lookup("name").StringValueOK()
		if t, _, ok := m.Lookup("electionTime").TimestampOK(); ok {
			row.ElectionTime = time.Unix(int64(t), 0).UTC()
		}
	}

	if selfPrimary {
		row.ElectionReason, _ = status.Lookup("electionCandidateMetrics", "lastElectionReason").StringValueOK()
	}

	return membersFromReplStatus(status)
}

func describeError(err error, viaShardMap bool) string {
	if err == nil {
		return ""
	}

	code := errorCode(err)

	switch {
	case errors.Is(err, mongo.ErrNoDocuments):
		return "oplog is empty"
	case errors.Is(err, errNoCollStats) || code == codeNamespaceNotFound || code == codeCollStatsNotFound:
		return "no oplog collection"
	case isAuthError(err):
		if viaShardMap {
			return "authentication failed; users created via mongos exist only on the config servers; " +
				"create a shard-local user"
		}

		return "authentication failed"
	case strings.Contains(err.Error(), "requires authentication"):
		return "no login: pass --username/--password"
	case code == codeUnauthorized:
		return "not authorized to read local.oplog.rs"
	case errors.As(err, &topology.ServerSelectionError{}):
		return "unreachable from this host"
	case errors.Is(err, context.DeadlineExceeded) || mongo.IsTimeout(err):
		return "timed out"
	}

	var ce mongo.CommandError
	if errors.As(err, &ce) && ce.Name != "" {
		return "failed: " + ce.Name
	}

	return "failed: " + err.Error()
}

func isAuthError(err error) bool {
	var ae *auth.Error

	return errors.As(err, &ae) || errorCode(err) == codeAuthenticationFailed
}

func answered(err error) bool {
	var ce mongo.CommandError

	return errors.Is(err, mongo.ErrNoDocuments) || errors.Is(err, errNoCollStats) || errors.Is(err, errNoTimestamp) ||
		(errors.As(err, &ce) && !mongo.IsTimeout(err))
}

func errorCode(err error) int32 {
	var ce mongo.CommandError
	if errors.As(err, &ce) {
		return ce.Code
	}

	var de driver.Error
	if errors.As(err, &de) {
		return de.Code
	}

	return 0
}

func runCommand(ctx context.Context, client *mongo.Client, name string) (bson.Raw, error) {
	raw, err := client.Database("admin").RunCommand(ctx, bson.D{{Key: name, Value: 1}}).Raw()
	if err != nil {
		return nil, err
	}

	return append(bson.Raw(nil), raw...), nil
}

func maxTime(ctx context.Context) (time.Duration, bool) {
	deadline, ok := ctx.Deadline()
	if !ok {
		return 0, false
	}

	return max(time.Until(deadline), time.Millisecond), true
}

func running(hours float64) string {
	if hours > 24 {
		return fmt.Sprintf("%0.2f days", hours/24)
	}

	return fmt.Sprintf("%0.2f hours", hours)
}

func documents(doc bson.Raw, key string) []bson.Raw {
	arr, ok := doc.Lookup(key).ArrayOK()
	if !ok {
		return nil
	}

	values, err := arr.Values()
	if err != nil {
		return nil
	}

	var docs []bson.Raw
	for _, v := range values {
		if d, ok := v.DocumentOK(); ok {
			docs = append(docs, d)
		}
	}

	return docs
}

func strs(doc bson.Raw, key string) []string {
	arr, ok := doc.Lookup(key).ArrayOK()
	if !ok {
		return nil
	}

	values, err := arr.Values()
	if err != nil {
		return nil
	}

	var out []string
	for _, v := range values {
		if s, ok := v.StringValueOK(); ok {
			out = append(out, s)
		}
	}

	return out
}

func number(v bson.RawValue) (float64, bool) {
	if i, ok := v.Int32OK(); ok {
		return float64(i), true
	}

	if i, ok := v.Int64OK(); ok {
		return float64(i), true
	}

	f, ok := v.DoubleOK()

	return f, ok && !math.IsNaN(f) && !math.IsInf(f, 0)
}

func intValue(doc bson.Raw, path ...string) (int64, bool) {
	v, err := doc.LookupErr(path...)
	if err != nil {
		return 0, false
	}

	if i, ok := v.Int32OK(); ok {
		return int64(i), true
	}

	if i, ok := v.Int64OK(); ok {
		return i, true
	}

	f, ok := v.DoubleOK()
	if !ok || f != math.Trunc(f) || math.Abs(f) >= math.MaxInt64 {
		return 0, false
	}

	return int64(f), true
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}

	return false
}

func sortMembers(members []Member) {
	sort.SliceStable(members, func(i, j int) bool {
		if members[i].Set != members[j].Set {
			return members[i].Set < members[j].Set
		}

		return members[i].Host < members[j].Host
	})
}
