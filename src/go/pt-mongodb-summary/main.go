package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"html/template"
	"io/ioutil"
	"net"
	"os"
	"os/user"
	"path/filepath"
	"strings"
	"time"

	version "github.com/hashicorp/go-version"
	"github.com/howeyc/gopass"
	"github.com/pborman/getopt"
	"github.com/pkg/errors"
	"github.com/shirou/gopsutil/process"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/oplog"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/templates"
)

const (
	TOOLNAME = "pt-mongodb-summary"

	DefaultAuthDB             = "admin"
	DefaultHost               = "mongodb://localhost:27017"
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
	Build     string = "2020-04-23"
	GoVersion string = "1.14.1"
	Version   string = "3.5.0"
	Commit    string

	defaultConnectionTimeout = 3 * time.Second
	directConnection         = true
)

type TimedStats struct {
	Min   int64
	Max   int64
	Total int64
	Avg   int64
}

type opCounters struct {
	Insert     TimedStats
	Query      TimedStats
	Update     TimedStats
	Delete     TimedStats
	GetMore    TimedStats
	Command    TimedStats
	SampleRate time.Duration
}

type hostInfo struct {
	Hostname          string
	HostOsType        string
	HostSystemCPUArch string
	HostDatabases     int
	HostCollections   int
	DBPath            string

	ProcPath         string
	ProcUserName     string
	ProcCreateTime   time.Time
	ProcProcessCount int

	CmdlineArgs []string
	// Server Status
	ProcessName    string
	ReplicasetName string
	Version        string
	NodeType       string
}

type procInfo struct {
	CreateTime time.Time
	Path       string
	UserName   string
	Error      error
}

type security struct {
	Users       int64
	Roles       int64
	Auth        string
	SSL         string
	BindIP      string
	Port        int64
	WarningMsgs []string
}

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
	Host               string
	User               string
	Password           string
	AuthDB             string
	LogLevel           string
	OutputFormat       string
	SSLCAFile          string
	SSLPEMKeyFile      string
	RunningOpsSamples  int
	RunningOpsInterval int
	Help               bool
	Version            bool
	NoVersionCheck     bool
	NoRunningOps       bool
}

type collectedInfo struct {
	BalancerStats    *proto.BalancerStats
	ClusterWideInfo  *clusterwideInfo
	OplogInfo        []proto.OplogInfo
	ReplicaMembers   []proto.Members
	RunningOps       *opCounters
	SecuritySettings *security
	HostInfo         *hostInfo
	Errors           []string
}

func main() {
	opts, err := parseFlags()
	if err != nil {
		log.Errorf("cannot get parameters: %s", err.Error())

		os.Exit(cannotParseCommandLineParameters)
	}

	if opts == nil && err == nil {
		return
	}

	logLevel, err := log.ParseLevel(opts.LogLevel)
	if err != nil {
		fmt.Printf("cannot set log level: %s", err.Error())
	}

	log.SetLevel(logLevel)

	if opts.Version {
		fmt.Println(TOOLNAME)
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)

		return
	}

	conf := config.DefaultConfig(TOOLNAME)
	if !conf.GetBool("no-version-check") && !opts.NoVersionCheck {
		advice, err := versioncheck.CheckUpdates(TOOLNAME, Version)
		if err != nil {
			log.Infof("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Infof(advice)
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

	hostnames, err := util.GetHostnames(ctx, client)
	if err != nil && errors.Is(err, util.ShardingNotEnabledError) {
		log.Errorf("Cannot get hostnames: %s", err)
	}

	log.Debugf("hostnames: %v", hostnames)

	ci := &collectedInfo{}

	ci.HostInfo, err = getHostInfo(ctx, client)
	if err != nil {
		log.Errorf("Cannot get host info for %q: %s", opts.Host, err)
		os.Exit(cannotGetHostInfo) //nolint:gocritic
	}

	if ci.ReplicaMembers, err = util.GetReplicasetMembers(ctx, clientOptions); err != nil {
		log.Warnf("[Error] cannot get replicaset members: %v\n", err)
	}

	log.Debugf("replicaMembers:\n%+v\n", ci.ReplicaMembers)

	if opts.RunningOpsSamples > 0 && opts.RunningOpsInterval > 0 {
		ci.RunningOps, err = getOpCountersStats(
			ctx, client, opts.RunningOpsSamples,
			time.Duration(opts.RunningOpsInterval)*time.Millisecond,
		)
		if err != nil {
			log.Printf("[Error] cannot get Opcounters stats: %v\n", err)
		}
	}

	if ci.HostInfo != nil {
		if ci.SecuritySettings, err = getSecuritySettings(ctx, client, ci.HostInfo.Version); err != nil {
			log.Errorf("[Error] cannot get security settings: %v\n", err)
		}
	} else {
		log.Warn("Cannot check security settings since host info is not available (permissions?)")
	}

	if ci.OplogInfo, err = oplog.GetOplogInfo(ctx, hostnames, clientOptions); err != nil {
		log.Infof("Cannot get Oplog info: %s\n", err)
	} else {
		if len(ci.OplogInfo) == 0 {
			log.Info("oplog info is empty. Skipping")
		} else {
			ci.OplogInfo = ci.OplogInfo[:1]
		}
	}

	// individual servers won't know about this info
	if ci.HostInfo.NodeType == typeMongos {
		if ci.ClusterWideInfo, err = getClusterwideInfo(ctx, client); err != nil {
			log.Printf("[Error] cannot get cluster wide info: %v\n", err)
		}
	}

	if ci.HostInfo.NodeType == typeMongos {
		if ci.BalancerStats, err = GetBalancerStats(ctx, client); err != nil {
			log.Printf("[Error] cannot get balancer stats: %v\n", err)
		}
	}

	out, err := formatResults(ci, opts.OutputFormat)
	if err != nil {
		log.Errorf("Cannot format the results: %s", err)
		os.Exit(cannotFormatResults)
	}

	fmt.Println(string(out))
}

func formatResults(ci *collectedInfo, format string) ([]byte, error) {
	var buf *bytes.Buffer

	switch format {
	case "json":
		b, err := json.MarshalIndent(ci, "", "    ")
		if err != nil {
			return nil, errors.Wrap(err, "Cannot convert results to json")
		}

		buf = bytes.NewBuffer(b)
	default:
		buf = new(bytes.Buffer)

		t := template.Must(template.New("replicas").Parse(templates.Replicas))
		if err := t.Execute(buf, ci.ReplicaMembers); err != nil {
			return nil, errors.Wrap(err, "cannot parse replicas section of the output template")
		}

		t = template.Must(template.New("hosttemplateData").Parse(templates.HostInfo))
		if err := t.Execute(buf, ci.HostInfo); err != nil {
			return nil, errors.Wrap(err, "cannot parse hosttemplateData section of the output template")
		}

		t = template.Must(template.New("cmdlineargsa").Parse(templates.CmdlineArgs))
		if err := t.Execute(buf, ci.HostInfo); err != nil {
			return nil, errors.Wrap(err, "cannot parse the command line args section of the output template")
		}

		t = template.Must(template.New("runningOps").Parse(templates.RunningOps))
		if err := t.Execute(buf, ci.RunningOps); err != nil {
			return nil, errors.Wrap(err, "cannot parse runningOps section of the output template")
		}

		t = template.Must(template.New("ssl").Parse(templates.Security))
		if err := t.Execute(buf, ci.SecuritySettings); err != nil {
			return nil, errors.Wrap(err, "cannot parse ssl section of the output template")
		}

		if ci.OplogInfo != nil && len(ci.OplogInfo) > 0 {
			t = template.Must(template.New("oplogInfo").Parse(templates.Oplog))
			if err := t.Execute(buf, ci.OplogInfo[0]); err != nil {
				return nil, errors.Wrap(err, "cannot parse oplogInfo section of the output template")
			}
		}

		t = template.Must(template.New("clusterwide").Parse(templates.Clusterwide))
		if err := t.Execute(buf, ci.ClusterWideInfo); err != nil {
			return nil, errors.Wrap(err, "cannot parse clusterwide section of the output template")
		}

		t = template.Must(template.New("balancer").Parse(templates.BalancerStats))
		if err := t.Execute(buf, ci.BalancerStats); err != nil {
			return nil, errors.Wrap(err, "cannot parse balancer section of the output template")
		}
	}

	return buf.Bytes(), nil
}

func getHostInfo(ctx context.Context, client *mongo.Client) (*hostInfo, error) {
	hi := proto.HostInfo{}
	if err := client.Database("admin").RunCommand(ctx, primitive.M{"hostInfo": 1}).Decode(&hi); err != nil {
		log.Debugf("run('hostInfo') error: %s", err)

		return nil, errors.Wrap(err, "GetHostInfo.hostInfo")
	}

	cmdOpts := proto.CommandLineOptions{}
	query := primitive.D{{Key: "getCmdLineOpts", Value: 1}, {Key: "recordStats", Value: 1}}
	err := client.Database("admin").RunCommand(ctx, query).Decode(&cmdOpts)
	if err != nil {
		return nil, errors.Wrap(err, "cannot get command line options")
	}

	ss := proto.ServerStatus{}
	query = primitive.D{{Key: "serverStatus", Value: 1}, {Key: "recordStats", Value: 1}}
	if err := client.Database("admin").RunCommand(ctx, query).Decode(&ss); err != nil {
		return nil, errors.Wrap(err, "GetHostInfo.serverStatus")
	}

	pi := procInfo{}
	if err := getProcInfo(int32(ss.Pid), &pi); err != nil {
		pi.Error = err
	}

	nodeType, _ := getNodeType(ctx, client)
	procCount, _ := countMongodProcesses()

	i := &hostInfo{
		Hostname:          hi.System.Hostname,
		HostOsType:        hi.Os.Type,
		HostSystemCPUArch: hi.System.CpuArch,
		DBPath:            "", // Sets default. It will be overridden later if necessary

		ProcessName:      ss.Process,
		ProcProcessCount: procCount,
		Version:          ss.Version,
		NodeType:         nodeType,

		ProcPath:       pi.Path,
		ProcUserName:   pi.UserName,
		ProcCreateTime: pi.CreateTime,
		CmdlineArgs:    cmdOpts.Argv,
	}
	if ss.Repl != nil {
		i.ReplicasetName = ss.Repl.SetName
	}

	if cmdOpts.Parsed.Storage.DbPath != "" {
		i.DBPath = cmdOpts.Parsed.Storage.DbPath
	}

	return i, nil
}

func countMongodProcesses() (int, error) {
	pids, err := process.Pids()
	if err != nil {
		return 0, err
	}

	count := 0

	for _, pid := range pids {
		p, err := process.NewProcess(pid)
		if err != nil {
			continue
		}

		if name, _ := p.Name(); name == "mongod" || name == typeMongos {
			count++
		}
	}
	return count, nil
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
	unit := []string{"bytes", "KB", "MB", "GB", "TB"}
	idx := 0
	newSize := float64(size)

	for newSize > 1024 {
		newSize /= 1024
		idx++
	}

	newSize = float64(int64(newSize*100)) / 100

	return newSize, unit[idx]
}

func getSecuritySettings(ctx context.Context, client *mongo.Client, ver string) (*security, error) {
	s := security{
		Auth: "disabled",
		SSL:  "disabled",
	}

	v26, _ := version.NewVersion("2.6")
	mongoVersion, err := version.NewVersion(ver)
	prior26 := false
	if err == nil && mongoVersion.LessThan(v26) {
		prior26 = true
	}

	cmdOpts := proto.CommandLineOptions{}
	err = client.Database("admin").RunCommand(ctx, primitive.D{
		{Key: "getCmdLineOpts", Value: 1},
		{Key: "recordStats", Value: 1},
	}).Decode(&cmdOpts)
	if err != nil {
		return nil, errors.Wrap(err, "cannot get command line options")
	}

	if cmdOpts.Security.Authorization != "" || cmdOpts.Security.KeyFile != "" ||
		cmdOpts.Parsed.Security.Authorization != "" || cmdOpts.Parsed.Security.KeyFile != "" {
		s.Auth = "enabled"
	}

	if cmdOpts.Parsed.Net.SSL.Mode != "" && cmdOpts.Parsed.Net.SSL.Mode != "disabled" {
		s.SSL = cmdOpts.Parsed.Net.SSL.Mode
	}

	s.BindIP = cmdOpts.Parsed.Net.BindIP
	s.Port = cmdOpts.Parsed.Net.Port

	if cmdOpts.Parsed.Net.BindIP == "" { //nolint:nestif
		if prior26 {
			s.WarningMsgs = append(s.WarningMsgs, "WARNING: You might be insecure. There is no IP binding")
		}
	} else {
		ips := strings.Split(cmdOpts.Parsed.Net.BindIP, ",")
		extIP, _ := externalIP()
		for _, ip := range ips {
			isPrivate, err := isPrivateNetwork(strings.TrimSpace(ip))
			if !isPrivate && err == nil {
				if s.Auth == "enabled" {
					s.WarningMsgs = append(
						s.WarningMsgs,
						fmt.Sprintf("Warning: You might be insecure (bind ip %s is public)", ip),
					)
				} else {
					s.WarningMsgs = append(
						s.WarningMsgs,
						fmt.Sprintf("Error. You are insecure: bind ip %s is public and auth is disabled", ip),
					)
				}
			} else {
				if ip != "127.0.0.1" && ip != extIP {
					s.WarningMsgs = append(
						s.WarningMsgs,
						fmt.Sprintf("WARNING: You might be insecure. IP binding %s is not localhost", ip),
					)
				}
			}
		}
	}

	if s.Users, s.Roles, err = getUserRolesCount(ctx, client); err != nil {
		if s.Users, s.Roles, err = getUserRolesCount(ctx, client); err != nil {
			return nil, errors.Wrap(err, "cannot get security settings.")
		}
	}

	return &s, nil
}

func getUserRolesCount(ctx context.Context, client *mongo.Client) (int64, int64, error) {
	users, err := client.Database("admin").Collection("system.users").CountDocuments(ctx, primitive.M{})
	if err != nil {
		return 0, 0, errors.Wrap(err, "cannot get users count")
	}

	roles, err := client.Database("admin").Collection("system.roles").CountDocuments(ctx, primitive.M{})
	if err != nil {
		return 0, 0, errors.Wrap(err, "cannot get roles count")
	}
	return users, roles, nil
}

func getNodeType(ctx context.Context, client *mongo.Client) (string, error) {
	md := proto.MasterDoc{}
	if err := client.Database("admin").RunCommand(ctx, primitive.M{"isMaster": 1}).Decode(&md); err != nil {
		return "", err
	}

	if md.SetName != nil || md.Hosts != nil {
		return "replset", nil
	} else if md.Msg == "isdbgrid" {
		// isdbgrid is always the msg value when calling isMaster on a mongos
		// see http://docs.mongodb.org/manual/core/sharded-cluster-query-router/
		return typeMongos, nil
	}
	return "mongod", nil
}

func getOpCountersStats(ctx context.Context, client *mongo.Client, count int,
	sleep time.Duration,
) (*opCounters, error) {
	oc := &opCounters{}
	prevOpCount := &opCounters{}
	ss := proto.ServerStatus{}
	delta := proto.ServerStatus{
		Opcounters: &proto.OpcountStats{},
	}

	ticker := time.NewTicker(sleep)
	// count + 1 because we need 1st reading to stablish a base to measure variation
	for i := 0; i < count+1; i++ {
		<-ticker.C

		err := client.Database("admin").RunCommand(ctx, primitive.D{
			{Key: "serverStatus", Value: 1},
			{Key: "recordStats", Value: 1},
		}).Decode(&ss)
		if err != nil {
			return nil, err
		}

		if i == 0 {
			prevOpCount.Command.Total = ss.Opcounters.Command
			prevOpCount.Delete.Total = ss.Opcounters.Delete
			prevOpCount.GetMore.Total = ss.Opcounters.GetMore
			prevOpCount.Insert.Total = ss.Opcounters.Insert
			prevOpCount.Query.Total = ss.Opcounters.Query
			prevOpCount.Update.Total = ss.Opcounters.Update

			continue
		}

		delta.Opcounters.Command = ss.Opcounters.Command - prevOpCount.Command.Total
		delta.Opcounters.Delete = ss.Opcounters.Delete - prevOpCount.Delete.Total
		delta.Opcounters.GetMore = ss.Opcounters.GetMore - prevOpCount.GetMore.Total
		delta.Opcounters.Insert = ss.Opcounters.Insert - prevOpCount.Insert.Total
		delta.Opcounters.Query = ss.Opcounters.Query - prevOpCount.Query.Total
		delta.Opcounters.Update = ss.Opcounters.Update - prevOpCount.Update.Total

		// Be careful. This cannot be item[0] because we need: value - prev_value
		// and at pos 0 there is no prev value
		if i == 1 {
			oc.Command.Max = delta.Opcounters.Command
			oc.Command.Min = delta.Opcounters.Command

			oc.Delete.Max = delta.Opcounters.Delete
			oc.Delete.Min = delta.Opcounters.Delete

			oc.GetMore.Max = delta.Opcounters.GetMore
			oc.GetMore.Min = delta.Opcounters.GetMore

			oc.Insert.Max = delta.Opcounters.Insert
			oc.Insert.Min = delta.Opcounters.Insert

			oc.Query.Max = delta.Opcounters.Query
			oc.Query.Min = delta.Opcounters.Query

			oc.Update.Max = delta.Opcounters.Update
			oc.Update.Min = delta.Opcounters.Update
		}

		// Insert --------------------------------------
		switch {
		case delta.Opcounters.Insert > oc.Insert.Max:
			oc.Insert.Max = delta.Opcounters.Insert
		case delta.Opcounters.Insert < oc.Insert.Min:
			oc.Insert.Min = delta.Opcounters.Insert
		}

		oc.Insert.Total += delta.Opcounters.Insert

		// Query ---------------------------------------
		switch {
		case delta.Opcounters.Query > oc.Query.Max:
			oc.Query.Max = delta.Opcounters.Query
		case delta.Opcounters.Query < oc.Query.Min:
			oc.Query.Min = delta.Opcounters.Query
		}

		oc.Query.Total += delta.Opcounters.Query

		// Command -------------------------------------
		switch {
		case delta.Opcounters.Command > oc.Command.Max:
			oc.Command.Max = delta.Opcounters.Command
		case delta.Opcounters.Command < oc.Command.Min:
			oc.Command.Min = delta.Opcounters.Command
		}

		oc.Command.Total += delta.Opcounters.Command

		// Update --------------------------------------
		switch {
		case delta.Opcounters.Update > oc.Update.Max:
			oc.Update.Max = delta.Opcounters.Update
		case delta.Opcounters.Update < oc.Update.Min:
			oc.Update.Min = delta.Opcounters.Update
		}

		oc.Update.Total += delta.Opcounters.Update

		// Delete --------------------------------------
		switch {
		case delta.Opcounters.Delete > oc.Delete.Max:
			oc.Delete.Max = delta.Opcounters.Delete
		case delta.Opcounters.Delete < oc.Delete.Min:
			oc.Delete.Min = delta.Opcounters.Delete
		}

		oc.Delete.Total += delta.Opcounters.Delete

		// GetMore -------------------------------------
		switch {
		case delta.Opcounters.GetMore > oc.GetMore.Max:
			oc.GetMore.Max = delta.Opcounters.GetMore
		case delta.Opcounters.GetMore < oc.GetMore.Min:
			oc.GetMore.Min = delta.Opcounters.GetMore
		}

		oc.GetMore.Total += delta.Opcounters.GetMore

		prevOpCount.Insert.Total = ss.Opcounters.Insert
		prevOpCount.Query.Total = ss.Opcounters.Query
		prevOpCount.Command.Total = ss.Opcounters.Command
		prevOpCount.Update.Total = ss.Opcounters.Update
		prevOpCount.Delete.Total = ss.Opcounters.Delete
		prevOpCount.GetMore.Total = ss.Opcounters.GetMore
	}

	ticker.Stop()

	oc.Insert.Avg = oc.Insert.Total
	oc.Query.Avg = oc.Query.Total
	oc.Update.Avg = oc.Update.Total
	oc.Delete.Avg = oc.Delete.Total
	oc.GetMore.Avg = oc.GetMore.Total
	oc.Command.Avg = oc.Command.Total
	//
	oc.SampleRate = time.Duration(count) * sleep

	return oc, nil
}

func getProcInfo(pid int32, templateData *procInfo) error {
	// proc, err := process.NewProcess(templateData.ServerStatus.Pid)
	proc, err := process.NewProcess(pid)
	if err != nil {
		return errors.New(fmt.Sprintf("cannot get process %d", pid))
	}

	ct, err := proc.CreateTime()
	if err != nil {
		return err
	}

	templateData.CreateTime = time.Unix(ct/1000, 0)
	templateData.Path, err = proc.Exe()
	if err != nil {
		return err
	}

	templateData.UserName, err = proc.Username()
	if err != nil {
		return err
	}
	return nil
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

func isPrivateNetwork(ip string) (bool, error) {
	privateCIDRs := []string{"10.0.0.0/24", "172.16.0.0/20", "192.168.0.0/16"}

	if net.ParseIP(ip).String() == "127.0.0.1" {
		return true, nil
	}

	for _, cidr := range privateCIDRs {
		_, cidrnet, err := net.ParseCIDR(cidr)
		if err != nil {
			return false, err
		}

		addr := net.ParseIP(ip)
		if cidrnet.Contains(addr) {
			return true, nil
		}
	}

	return false, nil
}

func externalIP() (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}

	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 {
			continue // interface down
		}

		if iface.Flags&net.FlagLoopback != 0 {
			continue // loopback interface
		}

		addrs, err := iface.Addrs()
		if err != nil {
			return "", err
		}

		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}

			if ip == nil || ip.IsLoopback() {
				continue
			}

			ip = ip.To4()
			if ip == nil {
				continue // not an ipv4 address
			}
			return ip.String(), nil
		}
	}

	return "", errors.New("are you connected to the network?")
}

func parseFlags() (*cliOptions, error) {
	opts := &cliOptions{
		Host:               DefaultHost,
		LogLevel:           DefaultLogLevel,
		RunningOpsSamples:  DefaultRunningOpsSamples,
		RunningOpsInterval: DefaultRunningOpsInterval, // milliseconds
		AuthDB:             DefaultAuthDB,
		OutputFormat:       DefaultOutputFormat,
	}

	gop := getopt.New()
	gop.BoolVarLong(&opts.Help, "help", 'h', "Show help")
	gop.BoolVarLong(&opts.Version, "version", 'v', "", "Show version & exit")
	gop.BoolVarLong(&opts.NoVersionCheck, "no-version-check", 'c', "", "Default: Don't check for updates")

	gop.StringVarLong(&opts.User, "username", 'u', "", "Username to use for optional MongoDB authentication")
	gop.StringVarLong(&opts.Password, "password", 'p', "", "Password to use for optional MongoDB authentication").
		SetOptional()
	gop.StringVarLong(&opts.AuthDB, "authenticationDatabase", 'a', "admin",
		"Database to use for optional MongoDB authentication. Default: admin")
	gop.StringVarLong(&opts.LogLevel, "log-level", 'l', "error",
		"Log level: panic, fatal, error, warn, info, debug. Default: error")
	gop.StringVarLong(&opts.OutputFormat, "output-format", 'f', "text", "Output format: text, json. Default: text")

	gop.IntVarLong(&opts.RunningOpsSamples, "running-ops-samples", 's',
		fmt.Sprintf("Number of samples to collect for running ops. Default: %d", opts.RunningOpsSamples),
	)

	gop.IntVarLong(&opts.RunningOpsInterval, "running-ops-interval", 'i',
		fmt.Sprintf("Interval to wait betwwen running ops samples in milliseconds. Default %d milliseconds",
			opts.RunningOpsInterval),
	)

	gop.StringVarLong(&opts.SSLCAFile, "sslCAFile", 0, "SSL CA cert file used for authentication")
	gop.StringVarLong(&opts.SSLPEMKeyFile, "sslPEMKeyFile", 0, "SSL client PEM file used for authentication")

	gop.SetParameters("host[:port]")
	gop.Parse(os.Args)

	if gop.NArgs() > 0 {
		opts.Host = gop.Arg(0)
		gop.Parse(gop.Args())
	}

	if gop.IsSet("password") && opts.Password == "" {
		print("Password: ")

		pass, err := gopass.GetPasswd()
		if err != nil {
			return opts, err
		}

		opts.Password = string(pass)
	}

	if !strings.HasPrefix(opts.Host, "mongodb://") {
		opts.Host = "mongodb://" + opts.Host
	}

	if opts.Help {
		gop.PrintUsage(os.Stdout)

		return nil, nil
	}

	if opts.OutputFormat != "json" && opts.OutputFormat != "text" {
		log.Infof("Invalid output format '%s'. Using text format", opts.OutputFormat)
	}

	return opts, nil
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
	clientOptions := options.Client().ApplyURI(opts.Host)

	clientOptions.ServerSelectionTimeout = &defaultConnectionTimeout
	clientOptions.Direct = &directConnection
	credential := options.Credential{}
	if opts.User != "" {
		credential.Username = opts.User
		clientOptions.SetAuth(credential)
	}

	if opts.Password != "" {
		credential.Password = opts.Password
		credential.PasswordSet = true
		clientOptions.SetAuth(credential)
	}

	if opts.SSLPEMKeyFile != "" || opts.SSLCAFile != "" {
		tlsConfig, err := getTLSConfig(opts.SSLPEMKeyFile, opts.SSLCAFile)
		if err != nil {
			return nil, errors.Wrap(err, "cannot read SSL certificate files")
		}

		clientOptions.TLSConfig = tlsConfig
	}

	return clientOptions, nil
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
