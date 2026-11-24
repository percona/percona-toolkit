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
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/alecthomas/kong"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/x/mongo/driver/connstring"
	"golang.org/x/term"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
)

const (
	toolname = "pt-mongodb-summary"

	DefaultAuthDB             = "admin"
	DefaultHost               = "localhost"
	DefaultPort               = "27017"
	DefaultLogLevel           = "warn"
	DefaultRunningOpsInterval = 1000 // milliseconds
	DefaultRunningOpsSamples  = 5
	DefaultOutputFormat       = "text"
	typeMongos                = "mongos"

	// Exit Codes.
	cannotFormatResults              = 1
	cannotParseCommandLineParameters = 2
	cannotGetHostInfo                = 3
	cannotGetClientOptions           = 4
	cannotConnectToMongoDB           = 5
)

//nolint:gochecknoglobals
var (
	// We do not set anything here, these variables are defined by the Makefile
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint

	defaultConnectionTimeout = 3 * time.Second
	directConnection         = true
)

type databases struct {
	Databases []struct {
		Name string `bson:"name"`
		// SizeOnDisk int64            `bson:"sizeOnDisk"`
		// Empty      bool             `bson:"empty"`
		// Shards     map[string]int64 `bson:"shards"`
	} `bson:"databases"`
	TotalSize   int64   `bson:"totalSize"`
	TotalSizeMb int64   `bson:"totalSizeMb"`
	OK          float64 `bson:"ok"`
}

type clusterwideInfo struct {
	TotalDBsCount           int
	TotalCollectionsCount   int
	ShardedColsCount        int
	UnshardedColsCount      int
	ShardedDataSize         int64 // bytes
	ShardedDataSizeScaled   float64
	ShardedDataSizeScale    string
	UnshardedDataSize       int64 // bytes
	UnshardedDataSizeScaled float64
	UnshardedDataSizeScale  string
	Chunks                  []proto.ChunksByCollection
}

type cliOptions struct {
	config.ConfigFlag
	config.VersionCheckFlag

	Version            bool                      `name:"version"                short:"v" help:"Show version and exit"`
	SkipVersionCheck   bool                      `name:"skip-version-check"     short:"c" hidden:""`
	URI                string                    `name:"uri"                    help:"MongoDB connection URI. Cannot be combined with --host or --port."`
	Host               string                    `name:"host"                   help:"Host to connect to"`
	Port               string                    `name:"port"                   help:"Port to connect to"`
	User               string                    `name:"username"               short:"u" help:"Username for MongoDB authentication"`
	Password           config.StdinRequestString `name:"password"               short:"p" help:"Password for MongoDB authentication. Omit the value to be prompted." optional:""`
	AuthDB             string                    `name:"authenticationDatabase" short:"a" help:"Authentication database (default: the authSource or database of --uri, else admin)"`
	LogLevel           string                    `name:"log-level"              short:"l" help:"Log level: panic, fatal, error, warn, info, debug" default:"warn"`
	OutputFormat       string                    `name:"output-format"          short:"f" help:"Output format: text or json" default:"text" enum:"text,json"`
	SSLCAFile          string                    `name:"sslCAFile"              help:"SSL CA cert file used for authentication"`
	SSLPEMKeyFile      string                    `name:"sslPEMKeyFile"          help:"SSL client PEM file used for authentication"`
	RunningOpsSamples  int                       `name:"running-ops-samples"    short:"s" help:"Number of samples to collect for running ops" default:"5"`
	RunningOpsInterval int                       `name:"running-ops-interval"   short:"i" help:"Interval between running ops samples in milliseconds" default:"1000"`

	HostPort string `arg:"" optional:"" name:"host[:port]" help:"Host and optional port"`
}

func (o *cliOptions) AfterApply() error {
	if o.Version {
		fmt.Println(toolname)
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)
		return nil
	}

	ll, err := log.ParseLevel(o.LogLevel)
	if err != nil {
		return fmt.Errorf("cannot set log level: %w", err)
	}
	log.SetLevel(ll)

	if err := o.Password.Request(func() (string, error) {
		print("Password: ")
		pass, err := term.ReadPassword(0)
		return string(pass), err
	}); err != nil {
		return err
	}

	if o.HostPort != "" {
		if o.URI != "" || o.Host != "" || o.Port != "" {
			return fmt.Errorf("host[:port] positional arg cannot be combined with --uri, --host, or --port")
		}
		host, port, splitErr := net.SplitHostPort(o.HostPort)
		if splitErr != nil {
			o.Host = o.HostPort
		} else {
			o.Host = host
			o.Port = port
		}
		o.HostPort = ""
	}

	if o.URI != "" && (o.Host != "" || o.Port != "") {
		return fmt.Errorf("if a full URI is provided, you cannot also specify --host or --port")
	}

	return nil
}

type collectedInfo struct {
	BalancerStats     *proto.BalancerStats
	ClusterWideInfo   *clusterwideInfo
	OplogInfo         []proto.OplogInfo
	ReplicaMembers    []proto.Members
	MemberDetails     []memberDetail
	RunningOps        *opCounters
	SecuritySettings  *security
	HostInfo          *hostInfo
	MongosInfo        *mongosInfo
	OSChecks          *osChecks
	StartupOptions    *startupOptions
	WiredTiger        *wiredTigerInfo
	Memory            *memoryInfo
	Connections       *connectionsInfo
	Profiling         *profilingInfo
	ChangeStreams     *changeStreamsInfo
	DatabaseInventory *dbInventory
	ShardsInfo        *shardsInfo
	Errors            []collectError
}

func main() {
	opts := &cliOptions{}
	if _, _, err := config.Setup(toolname, opts, kong.Exit(exitOnParseError)); err != nil {
		log.Errorf("cannot get parameters: %s", err)
		os.Exit(cannotParseCommandLineParameters)
	}

	if opts.Version {
		return
	}

	b := newBudget(rootBudget + samplingTime(opts))

	if opts.VersionCheck && !opts.SkipVersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Infof("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Infof("%s", advice)
		}
	}

	ctx := context.Background()
	clientOptions, err := getClientOptions(opts)
	if err != nil {
		log.Error(err)

		os.Exit(cannotGetClientOptions)
	}

	client, err := mongo.NewClient(clientOptions)
	if err != nil {
		log.Errorf("Cannot get a MongoDB client: %s", err)

		os.Exit(cannotConnectToMongoDB)
	}

	if err := client.Connect(ctx); err != nil {
		log.Errorf("Cannot connect to MongoDB: %s", err)
		os.Exit(cannotConnectToMongoDB)
	}

	defer client.Disconnect(ctx) // nolint

	start := time.Now()
	if err := pingServer(ctx, client, b); err != nil {
		log.Errorf("Cannot connect to MongoDB at %s after %s: %s%s", strings.Join(clientOptions.Hosts, ","),
			time.Since(start).Round(100*time.Millisecond), connectHint(err, clientOptions.TLSConfig != nil), err)
		os.Exit(cannotConnectToMongoDB) //nolint:gocritic
	}
	log.Debugf("ping took %s", time.Since(start))

	start = time.Now()
	sctx, cancel := b.ctx(ctx, snapshotCallTimeout)
	snap := takeSnapshot(sctx, client)
	cancel()
	log.Debugf("snapshot took %s", time.Since(start))

	start = time.Now()
	hctx, cancel := b.ctx(ctx, nodeCallTimeout)
	hi, err := getHostInfo(hctx, client, snap)
	cancel()
	if err != nil {
		log.Errorf("Cannot get host info for %q: %s", clientOptions.Hosts, err)
		os.Exit(cannotGetHostInfo) //nolint:gocritic
	}
	log.Debugf("host info took %s", time.Since(start))

	hi.CmdlineArgs = maskArgv(hi.CmdlineArgs)

	ci := collect(ctx, client, clientOptions, opts, b, snap, hi)

	out, err := formatResults(ci, opts.OutputFormat)
	if err != nil {
		log.Errorf("Cannot format the results: %s", err)
		os.Exit(cannotFormatResults)
	}

	fmt.Println(string(out))
}

func exitOnParseError(code int) {
	if code != 0 {
		code = cannotParseCommandLineParameters
	}
	os.Exit(code)
}

func collect(ctx context.Context, client *mongo.Client, co *options.ClientOptions, opts *cliOptions, b *budget,
	snap *snapshot, hi *hostInfo,
) *collectedInfo {
	ctx, cancel := b.ctx(ctx, b.remaining())
	defer cancel()

	ci := &collectedInfo{HostInfo: hi}
	g := &gaps{isArbiter: hi.IsArbiter}

	arbiter := hi.IsArbiter
	remoteArbiter := arbiter && snap.ServerStatusErr != nil
	mongos := hi.NodeType == typeMongos
	standalone := hi.NodeType == "mongod"
	sampling := samplingTime(opts)

	if remoteArbiter {
		g.note("Arbiter", "Arbiter",
			"accepts no logins; for full details run the tool on its host against localhost", true)
	}

	if !arbiter {
		g.add("This host", "Host facts", "hostInfo: clusterMonitor", snap.HostInfoErr)
	}

	if !remoteArbiter {
		g.add("Running Ops", "Server status", "serverStatus: clusterMonitor", snap.ServerStatusErr)
		g.add("Startup Options, Security", "Startup Options, Security", "getCmdLineOpts: clusterMonitor", snap.CmdLineOptsErr)
	}

	var samples opSampleSet
	runStage(b, g, "sampler", sampling > 0 && snap.ServerStatusErr == nil, func() {
		sctx, cancel := b.ctx(ctx, sampling+nodeCallTimeout)
		defer cancel()

		interval := time.Duration(opts.RunningOpsInterval) * time.Millisecond
		samples = sampleServerStatus(sctx, client, snap.ServerStatus, opts.RunningOpsSamples, interval)

		var err error
		if ci.RunningOps, err = summarizeRunningOps(samples, interval); err != nil {
			g.add("Running Ops", "Running Ops", "serverStatus: clusterMonitor", err)
		}
	}, collectError{Section: "Running Ops", Item: "Running Ops"})

	runStage(b, g, "fcv", !arbiter && !mongos, func() { fillFCV(ctx, client, hi, b, g) },
		collectError{Section: "This host", Item: "FCV"})
	runStage(b, g, "os checks", !arbiter || hi.IsLocal, func() { ci.OSChecks = getOSChecks(ctx, client, snap, hi, b, g) },
		collectError{Section: "OS & Production Checks", Item: "OS & Production Checks"})

	if !remoteArbiter {
		ci.StartupOptions = buildStartupOptions(snap)
		ci.WiredTiger = buildWiredTiger(snap, samples, g)
		ci.Memory = buildMemory(snap)
		ci.Connections = buildConnections(snap)
	}

	runStage(b, g, "profiling", !arbiter, func() { ci.Profiling = getProfiling(ctx, client, snap, hi, b, g) },
		collectError{Section: "Connections & Profiling", Item: "Profiling"})
	runStage(b, g, "security", !remoteArbiter, func() { ci.SecuritySettings = getSecuritySettings(ctx, client, snap, hi, b) },
		collectError{Section: "Security", Item: "Security"})

	sharding := []collectError{{Section: "Mongos", Item: "Mongos"}}
	if mongos {
		sharding = append(sharding, collectError{Section: "Shards", Item: "Shards"})
	}

	runStage(b, g, "sharding", mongos || snap.clusterRole() == "configsvr", func() {
		ci.MongosInfo, ci.ShardsInfo = getShardingInfo(ctx, client, snap, hi, b, g)
	}, sharding...)
	runStage(b, g, "member phase", !standalone, func() {
		ci.ReplicaMembers, ci.MemberDetails, ci.OplogInfo = memberPhase(ctx, client, co, snap, hi, b, g)
	}, collectError{Section: "Instances", Item: "Instances"}, collectError{Section: "Oplog", Item: "Oplog"})
	runStage(b, g, "change streams", !arbiter && !standalone && majorVersion(hi.Version) >= 6, func() {
		ci.ChangeStreams = getChangeStreams(ctx, client, snap, hi, b, g)
	}, collectError{Section: "Change Streams", Item: "Change Streams"})
	runStage(b, g, "database inventory", !arbiter, func() {
		ci.DatabaseInventory = getDatabaseInventory(ctx, mongoInventorySource{client: client}, snap, hi, b, g)
	}, collectError{Section: "Database Inventory", Item: "Database Inventory"})

	runStage(b, g, "cluster wide", mongos, func() {
		var err error
		if ci.ClusterWideInfo, err = getClusterwideInfo(ctx, client); err != nil {
			g.add("Cluster wide", "Cluster wide", "collStats on config system collections", err)
		}
	}, collectError{Section: "Cluster wide", Item: "Cluster wide"})
	runStage(b, g, "balancer", mongos, func() {
		var err error
		if ci.BalancerStats, err = GetBalancerStats(ctx, client); err != nil {
			g.add("Balancer (per day)", "Balancer (per day)", "", err)
		}
	}, collectError{Section: "Balancer (per day)", Item: "Balancer (per day)"})

	ci.Errors = g.list

	return ci
}

func runStage(b *budget, g *gaps, name string, applies bool, f func(), lost ...collectError) {
	if !applies {
		return
	}

	if b.expired() {
		for _, l := range lost {
			g.add(l.Section, l.Item, "", context.DeadlineExceeded)
		}

		return
	}

	start := time.Now()
	f()
	log.Debugf("%s took %s", name, time.Since(start))
}

func majorVersion(v string) int {
	major, _, _ := strings.Cut(v, ".")
	n, _ := strconv.Atoi(major)

	return n
}

func formatResults(ci *collectedInfo, format string) ([]byte, error) {
	if format == "json" {
		b, err := json.MarshalIndent(ci, "", "    ")
		if err != nil {
			return nil, errors.Wrap(err, "Cannot convert results to json")
		}

		return b, nil
	}

	return renderText(ci), nil
}

func getClusterwideInfo(ctx context.Context, client *mongo.Client) (*clusterwideInfo, error) {
	var databases databases

	err := client.Database("admin").RunCommand(ctx, primitive.M{"listDatabases": 1}).Decode(&databases)
	if err != nil {
		return nil, errors.Wrap(err, "getClusterwideInfo.listDatabases ")
	}

	cwi := &clusterwideInfo{
		TotalDBsCount: len(databases.Databases),
	}

	for _, db := range databases.Databases {
		cursor, err := client.Database(db.Name).ListCollections(ctx, primitive.M{})
		if err != nil {
			continue
		}

		for cursor.Next(ctx) {
			c := proto.CollectionEntry{}
			if err := cursor.Decode(&c); err != nil {
				return nil, errors.Wrap(err, "cannot decode ListCollections doc")
			}

			var collStats proto.CollStats
			err := client.Database(db.Name).RunCommand(ctx, primitive.M{"collStats": c.Name}).Decode(&collStats)
			if err != nil {
				return nil, errors.Wrapf(err, "cannot get info for collection %s.%s", db.Name, c.Name)
			}
			cwi.TotalCollectionsCount++

			if collStats.Sharded {
				cwi.ShardedDataSize += collStats.Size
				cwi.ShardedColsCount++

				continue
			}

			cwi.UnshardedDataSize += collStats.Size
			cwi.UnshardedColsCount++
		}
	}

	cwi.UnshardedColsCount = cwi.TotalCollectionsCount - cwi.ShardedColsCount
	cwi.ShardedDataSizeScaled, cwi.ShardedDataSizeScale = sizeAndUnit(cwi.ShardedDataSize)
	cwi.UnshardedDataSizeScaled, cwi.UnshardedDataSizeScale = sizeAndUnit(cwi.UnshardedDataSize)

	cwi.Chunks, err = getChunksCount(ctx, client)
	if err != nil {
		return nil, errors.Wrap(err, "cannot get chunks information")
	}

	return cwi, nil
}

func sizeAndUnit(size int64) (float64, string) {
	idx := 0
	newSize := float64(size)

	for newSize > 1024 && idx < len(byteUnits)-1 {
		newSize /= 1024
		idx++
	}

	newSize = float64(int64(newSize*100)) / 100

	return newSize, byteUnits[idx]
}

func GetBalancerStats(ctx context.Context, client *mongo.Client) (*proto.BalancerStats, error) {
	scs, err := GetShardingChangelogStatus(ctx, client)
	if err != nil {
		return nil, err
	}

	s := &proto.BalancerStats{}

	for _, item := range *scs.Items {
		event := item.Id.Event
		note := item.Id.Note
		count := item.Count

		switch event {
		case "moveChunk.to", "moveChunk.from", "moveChunk.commit":
			if note == "success" || note == "" {
				s.Success += int64(count)
			} else {
				s.Failed += int64(count)
			}
		case "split", "multi-split":
			s.Splits += int64(count)
		case "dropCollection", "dropCollection.start", "dropDatabase", "dropDatabase.start":
			s.Drops++
		}
	}

	return s, nil
}

func GetShardingChangelogStatus(ctx context.Context, client *mongo.Client) (*proto.ShardingChangelogStats, error) {
	qresults := []proto.ShardingChangelogSummary{}
	coll := client.Database("config").Collection("changelog")
	match := primitive.M{"time": primitive.M{"$gt": time.Now().Add(-240 * time.Hour)}}
	group := primitive.M{"_id": primitive.M{"event": "$what", "note": "$details.note"}, "count": primitive.M{"$sum": 1}}

	cursor, err := coll.Aggregate(ctx, []primitive.M{{"$match": match}, {"$group": group}})
	if err != nil {
		return nil, errors.Wrap(err, "GetShardingChangelogStatus.changelog.find")
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		res := proto.ShardingChangelogSummary{}
		if err := cursor.Decode(&res); err != nil {
			return nil, errors.Wrap(err, "cannot decode GetShardingChangelogStatus")
		}

		qresults = append(qresults, res)
	}

	return &proto.ShardingChangelogStats{
		Items: &qresults,
	}, nil
}

func getChunksCount(ctx context.Context, client *mongo.Client) ([]proto.ChunksByCollection, error) {
	var result []proto.ChunksByCollection

	c := client.Database("config").Collection("chunks")
	query := primitive.M{"$group": primitive.M{"_id": "$ns", "count": primitive.M{"$sum": 1}}}

	// db.getSiblingDB('config').chunks.aggregate({$group:{_id:"$ns",count:{$sum:1}}})
	cursor, err := c.Aggregate(ctx, []primitive.M{query})
	if err != nil {
		return nil, err
	}

	for cursor.Next(ctx) {
		res := proto.ChunksByCollection{}
		if err := cursor.Decode(&res); err != nil {
			return nil, errors.Wrap(err, "cannot decode chunks aggregation")
		}

		result = append(result, res)
	}

	return result, nil
}

func getClientOptions(opts *cliOptions) (*options.ClientOptions, error) {
	var clientOptions *options.ClientOptions

	if opts.URI != "" {
		clientOptions = options.Client().ApplyURI(opts.URI)
	} else {
		host := opts.Host
		if host == "" {
			host = DefaultHost
		}
		port := opts.Port
		if port == "" {
			port = DefaultPort
		}

		clientOptions = options.Client().ApplyURI("mongodb://" + net.JoinHostPort(host, port))
	}

	auth := clientOptions.Auth
	if auth == nil {
		auth = &options.Credential{}
	}

	if opts.User != "" {
		auth.Username = opts.User
	}
	if opts.Password != "" {
		auth.Password = string(opts.Password)
		auth.PasswordSet = true
	}
	if auth.Username != "" {
		switch {
		case opts.AuthDB != "" && usesExternalAuth(auth.AuthMechanism):
			log.Warnf("[Warning] --authenticationDatabase %s is ignored: %s authenticates against $external\n",
				opts.AuthDB, auth.AuthMechanism)
		case opts.AuthDB != "":
			auth.AuthSource = opts.AuthDB
		case auth.AuthSource == "" && opts.URI != "":
			if cs, err := connstring.Parse(opts.URI); err == nil {
				auth.AuthSource = cs.AuthSource
				if auth.AuthSource == "" {
					auth.AuthSource = cs.Database
				}
			}
		}
		clientOptions.SetAuth(*auth)
	}

	if opts.SSLPEMKeyFile != "" || opts.SSLCAFile != "" {
		tlsConfig, err := getTLSConfig(opts.SSLPEMKeyFile, opts.SSLCAFile)
		if err != nil {
			return nil, errors.Wrap(err, "cannot read SSL certificate files")
		}

		clientOptions.TLSConfig = tlsConfig
	}

	// Defaults
	if clientOptions.ServerSelectionTimeout == nil {
		clientOptions.ServerSelectionTimeout = &defaultConnectionTimeout
	}
	if clientOptions.Direct == nil {
		clientOptions.Direct = &directConnection
	}
	if clientOptions.Timeout == nil {
		clientOptions.SetTimeout(clientTimeout)
	}

	return clientOptions, clientOptions.Validate()
}

func getTLSConfig(sslPEMKeyFile, sslCAFile string) (*tls.Config, error) {
	tlsConfig := &tls.Config{
		MinVersion:         tls.VersionTLS10,
		InsecureSkipVerify: true,
	}

	roots := x509.NewCertPool()

	if sslPEMKeyFile != "" {
		crt, err := ioutil.ReadFile(filepath.Clean(expandHome(sslPEMKeyFile)))
		if err != nil {
			return nil, err
		}

		cert, err := tls.X509KeyPair(crt, crt)
		if err != nil {
			log.Fatal(err)
		}

		tlsConfig.Certificates = []tls.Certificate{cert}
	}

	if sslCAFile != "" {
		ca, err := ioutil.ReadFile(filepath.Clean(expandHome(sslCAFile)))
		if err != nil {
			return nil, err
		}

		roots.AppendCertsFromPEM(ca)
		tlsConfig.RootCAs = roots
	}

	return tlsConfig, nil
}

func expandHome(path string) string {
	usr, _ := user.Current()
	dir := usr.HomeDir

	switch {
	case path == "~":
		path = dir
	case strings.HasPrefix(path, "~/"):
		path = filepath.Join(dir, path[2:])
	}

	return path
}
