package main

import (
	"fmt"
	"net"
	"os"
	"strings"
	"text/template"
	"time"

	version "github.com/hashicorp/go-version"
	"github.com/howeyc/gopass"
	"github.com/pborman/getopt"
	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/oplog"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/templates"
	"github.com/percona/pmgo"
	"github.com/pkg/errors"
	"github.com/shirou/gopsutil/process"
	log "github.com/sirupsen/logrus"
	"gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
)

const (
	TOOLNAME = "pt-mongodb-summary"

	DEFAULT_AUTHDB             = "admin"
	DEFAULT_HOST               = "localhost:27017"
	DEFAULT_LOGLEVEL           = "warn"
	DEFAULT_RUNNINGOPSINTERVAL = 1000 // milliseconds
	DEFAULT_RUNNINGOPSSAMPLES  = 5
)

var (
	Build     string = "01-01-1980"
	GoVersion string = "1.8"
	Version   string = "3.0.1"
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
	Users       int
	Roles       int
	Auth        string
	SSL         string
	BindIP      string
	Port        int64
	WarningMsgs []string
}

type databases struct {
	Databases []struct {
		Name       string           `bson:"name"`
		SizeOnDisk int64            `bson:"sizeOnDisk"`
		Empty      bool             `bson:"empty"`
		Shards     map[string]int64 `bson:"shards"`
	} `bson:"databases"`
	TotalSize   int64 `bson:"totalSize"`
	TotalSizeMb int64 `bson:"totalSizeMb"`
	OK          bool  `bson:"ok"`
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

type options struct {
	Help               bool
	Host               string
	User               string
	Password           string
	AuthDB             string
	LogLevel           string
	Version            bool
	NoVersionCheck     bool
	NoRunningOps       bool
	RunningOpsSamples  int
	RunningOpsInterval int
	SSLCAFile          string
	SSLPEMKeyFile      string
}

func main() {

	opts, err := parseFlags()
	if err != nil {
		log.Errorf("cannot get parameters: %s", err.Error())
		os.Exit(2)
	}
	if opts == nil && err == nil {
		return
	}

	if opts.Help {
		getopt.Usage()
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
		return
	}

	conf := config.DefaultConfig(TOOLNAME)
	if !conf.GetBool("no-version-check") && !opts.NoVersionCheck {
		advice, err := versioncheck.CheckUpdates(TOOLNAME, Version)
		if err != nil {
			log.Infof("cannot check version updates: %s", err.Error())
		} else {
			if advice != "" {
				log.Infof(advice)
			}
		}
	}

	di := &pmgo.DialInfo{
		Username:      opts.User,
		Password:      opts.Password,
		Addrs:         []string{opts.Host},
		FailFast:      true,
		Source:        opts.AuthDB,
		SSLCAFile:     opts.SSLCAFile,
		SSLPEMKeyFile: opts.SSLPEMKeyFile,
	}

	log.Debugf("Connecting to the db using:\n%+v", di)
	dialer := pmgo.NewDialer()

	hostnames, err := util.GetHostnames(dialer, di)
	log.Debugf("hostnames: %v", hostnames)

	session, err := dialer.DialWithInfo(di)
	if err != nil {
		message := fmt.Sprintf("Cannot connect to %q", di.Addrs[0])
		if di.Username != "" || di.Password != "" {
			message += fmt.Sprintf(" using user: %q", di.Username)
			if strings.HasPrefix(di.Password, "=") {
				message += " (probably you are using = with -p or -u instead of a blank space)"
			}
		}
		message += fmt.Sprintf(". %s", err.Error())
		log.Errorf(message)
		os.Exit(1)
	}
	defer session.Close()
	session.SetMode(mgo.Monotonic, true)

	hostInfo, err := GetHostinfo(session)
	if err != nil {
		message := fmt.Sprintf("Cannot get host info for %q: %s", di.Addrs[0], err.Error())
		log.Errorf(message)
		os.Exit(2)
	}

	if replicaMembers, err := util.GetReplicasetMembers(dialer, di); err != nil {
		log.Warnf("[Error] cannot get replicaset members: %v\n", err)
		os.Exit(2)
	} else {
		log.Debugf("replicaMembers:\n%+v\n", replicaMembers)
		t := template.Must(template.New("replicas").Parse(templates.Replicas))
		t.Execute(os.Stdout, replicaMembers)
	}

	// Host Info
	t := template.Must(template.New("hosttemplateData").Parse(templates.HostInfo))
	t.Execute(os.Stdout, hostInfo)

	if opts.RunningOpsSamples > 0 && opts.RunningOpsInterval > 0 {
		if rops, err := GetOpCountersStats(session, opts.RunningOpsSamples, time.Duration(opts.RunningOpsInterval)*time.Millisecond); err != nil {
			log.Printf("[Error] cannot get Opcounters stats: %v\n", err)
		} else {
			t := template.Must(template.New("runningOps").Parse(templates.RunningOps))
			t.Execute(os.Stdout, rops)
		}
	}

	if hostInfo != nil {
		if security, err := GetSecuritySettings(session, hostInfo.Version); err != nil {
			log.Errorf("[Error] cannot get security settings: %v\n", err)
		} else {
			t := template.Must(template.New("ssl").Parse(templates.Security))
			t.Execute(os.Stdout, security)
		}
	} else {
		log.Warn("Cannot check security settings since host info is not available (permissions?)")
	}

	if oplogInfo, err := oplog.GetOplogInfo(hostnames, di); err != nil {
		log.Info("Cannot get Oplog info: %v\n", err)
	} else {
		if len(oplogInfo) > 0 {
			t := template.Must(template.New("oplogInfo").Parse(templates.Oplog))
			t.Execute(os.Stdout, oplogInfo[0])
		} else {

			log.Info("oplog info is empty. Skipping")
		}
	}

	// individual servers won't know about this info
	if hostInfo.NodeType == "mongos" {
		if cwi, err := GetClusterwideInfo(session); err != nil {
			log.Printf("[Error] cannot get cluster wide info: %v\n", err)
		} else {
			t := template.Must(template.New("clusterwide").Parse(templates.Clusterwide))
			t.Execute(os.Stdout, cwi)
		}
	}

	if hostInfo.NodeType == "mongos" {
		if bs, err := GetBalancerStats(session); err != nil {
			log.Printf("[Error] cannot get balancer stats: %v\n", err)
		} else {
			t := template.Must(template.New("balancer").Parse(templates.BalancerStats))
			t.Execute(os.Stdout, bs)
		}
	}

}

func GetHostinfo(session pmgo.SessionManager) (*hostInfo, error) {

	hi := proto.HostInfo{}
	if err := session.Run(bson.M{"hostInfo": 1}, &hi); err != nil {
		log.Debugf("run('hostInfo') error: %s", err.Error())
		return nil, errors.Wrap(err, "GetHostInfo.hostInfo")
	}

	cmdOpts := proto.CommandLineOptions{}
	err := session.DB("admin").Run(bson.D{{"getCmdLineOpts", 1}, {"recordStats", 1}}, &cmdOpts)
	if err != nil {
		return nil, errors.Wrap(err, "cannot get command line options")
	}

	ss := proto.ServerStatus{}
	if err := session.DB("admin").Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, &ss); err != nil {
		return nil, errors.Wrap(err, "GetHostInfo.serverStatus")
	}

	pi := procInfo{}
	if err := getProcInfo(int32(ss.Pid), &pi); err != nil {
		pi.Error = err
	}

	nodeType, _ := getNodeType(session)
	procCount, _ := countMongodProcesses()

	i := &hostInfo{
		Hostname:          hi.System.Hostname,
		HostOsType:        hi.Os.Type,
		HostSystemCPUArch: hi.System.CpuArch,
		DBPath:            "", // Sets default. It will be overriden later if necessary

		ProcessName:      ss.Process,
		ProcProcessCount: procCount,
		Version:          ss.Version,
		NodeType:         nodeType,

		ProcPath:       pi.Path,
		ProcUserName:   pi.UserName,
		ProcCreateTime: pi.CreateTime,
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
		if name, _ := p.Name(); name == "mongod" || name == "mongos" {
			count++
		}
	}
	return count, nil
}

func GetClusterwideInfo(session pmgo.SessionManager) (*clusterwideInfo, error) {
	var databases databases

	err := session.Run(bson.M{"listDatabases": 1}, &databases)
	if err != nil {
		return nil, errors.Wrap(err, "GetClusterwideInfo.listDatabases ")
	}

	cwi := &clusterwideInfo{
		TotalDBsCount: len(databases.Databases),
	}

	for _, db := range databases.Databases {
		collections, err := session.DB(db.Name).CollectionNames()
		if err != nil {
			continue
		}

		cwi.TotalCollectionsCount += len(collections)
		for _, collName := range collections {
			var collStats proto.CollStats
			err := session.DB(db.Name).Run(bson.M{"collStats": collName}, &collStats)
			if err != nil {
				continue
			}

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

	cwi.Chunks, _ = getChunksCount(session)

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

func GetSecuritySettings(session pmgo.SessionManager, ver string) (*security, error) {
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
	err = session.DB("admin").Run(bson.D{{"getCmdLineOpts", 1}, {"recordStats", 1}}, &cmdOpts)
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

	if cmdOpts.Parsed.Net.BindIP == "" {
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
					s.WarningMsgs = append(s.WarningMsgs, fmt.Sprintf("Warning: You might be insecure (bind ip %s is public)", ip))
				} else {
					s.WarningMsgs = append(s.WarningMsgs, fmt.Sprintf("Error. You are insecure: bind ip %s is public and auth is disabled", ip))
				}
			} else {
				if ip != "127.0.0.1" && ip != extIP {
					s.WarningMsgs = append(s.WarningMsgs, fmt.Sprintf("WARNING: You might be insecure. IP binding %s is not localhost"))
				}
			}
		}
	}

	// On some servers, like a mongos with config servers, this fails if session mode is Monotonic
	// On some other servers like a secondary in a replica set, this fails if the session mode is Strong.
	// Lets try both
	newSession := session.Clone()
	defer newSession.Close()
	newSession.SetMode(mgo.Strong, true)

	if s.Users, s.Roles, err = getUserRolesCount(newSession); err != nil {
		newSession.SetMode(mgo.Monotonic, true)
		if s.Users, s.Roles, err = getUserRolesCount(newSession); err != nil {
			return nil, errors.Wrap(err, "cannot get security settings.")
		}
	}

	return &s, nil
}

func getUserRolesCount(session pmgo.SessionManager) (int, int, error) {
	users, err := session.DB("admin").C("system.users").Count()
	if err != nil {
		return 0, 0, errors.Wrap(err, "cannot get users count")
	}

	roles, err := session.DB("admin").C("system.roles").Count()
	if err != nil {
		return 0, 0, errors.Wrap(err, "cannot get roles count")
	}
	return users, roles, nil
}

func getNodeType(session pmgo.SessionManager) (string, error) {
	md := proto.MasterDoc{}
	err := session.Run("isMaster", &md)
	if err != nil {
		return "", err
	}

	if md.SetName != nil || md.Hosts != nil {
		return "replset", nil
	} else if md.Msg == "isdbgrid" {
		// isdbgrid is always the msg value when calling isMaster on a mongos
		// see http://docs.mongodb.org/manual/core/sharded-cluster-query-router/
		return "mongos", nil
	}
	return "mongod", nil
}

func GetOpCountersStats(session pmgo.SessionManager, count int, sleep time.Duration) (*opCounters, error) {
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
		err := session.DB("admin").Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, &ss)
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
		if delta.Opcounters.Insert > oc.Insert.Max {
			oc.Insert.Max = delta.Opcounters.Insert
		}
		if delta.Opcounters.Insert < oc.Insert.Min {
			oc.Insert.Min = delta.Opcounters.Insert
		}
		oc.Insert.Total += delta.Opcounters.Insert

		// Query ---------------------------------------
		if delta.Opcounters.Query > oc.Query.Max {
			oc.Query.Max = delta.Opcounters.Query
		}
		if delta.Opcounters.Query < oc.Query.Min {
			oc.Query.Min = delta.Opcounters.Query
		}
		oc.Query.Total += delta.Opcounters.Query

		// Command -------------------------------------
		if delta.Opcounters.Command > oc.Command.Max {
			oc.Command.Max = delta.Opcounters.Command
		}
		if delta.Opcounters.Command < oc.Command.Min {
			oc.Command.Min = delta.Opcounters.Command
		}
		oc.Command.Total += delta.Opcounters.Command

		// Update --------------------------------------
		if delta.Opcounters.Update > oc.Update.Max {
			oc.Update.Max = delta.Opcounters.Update
		}
		if delta.Opcounters.Update < oc.Update.Min {
			oc.Update.Min = delta.Opcounters.Update
		}
		oc.Update.Total += delta.Opcounters.Update

		// Delete --------------------------------------
		if delta.Opcounters.Delete > oc.Delete.Max {
			oc.Delete.Max = delta.Opcounters.Delete
		}
		if delta.Opcounters.Delete < oc.Delete.Min {
			oc.Delete.Min = delta.Opcounters.Delete
		}
		oc.Delete.Total += delta.Opcounters.Delete

		// GetMore -------------------------------------
		if delta.Opcounters.GetMore > oc.GetMore.Max {
			oc.GetMore.Max = delta.Opcounters.GetMore
		}
		if delta.Opcounters.GetMore < oc.GetMore.Min {
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
	//proc, err := process.NewProcess(templateData.ServerStatus.Pid)
	proc, err := process.NewProcess(pid)
	if err != nil {
		return fmt.Errorf("cannot get process %d\n", pid)
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

func getDbsAndCollectionsCount(hostnames []string) (int, int, error) {
	dbnames := make(map[string]bool)
	colnames := make(map[string]bool)

	for _, hostname := range hostnames {
		session, err := mgo.Dial(hostname)
		if err != nil {
			continue
		}
		dbs, err := session.DatabaseNames()
		if err != nil {
			continue
		}

		for _, dbname := range dbs {
			dbnames[dbname] = true
			cols, err := session.DB(dbname).CollectionNames()
			if err != nil {
				continue
			}
			for _, colname := range cols {
				colnames[dbname+"."+colname] = true
			}
		}
	}

	return len(dbnames), len(colnames), nil
}

func GetBalancerStats(session pmgo.SessionManager) (*proto.BalancerStats, error) {

	scs, err := GetShardingChangelogStatus(session)
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

func GetShardingChangelogStatus(session pmgo.SessionManager) (*proto.ShardingChangelogStats, error) {
	var qresults []proto.ShardingChangelogSummary
	coll := session.DB("config").C("changelog")
	match := bson.M{"time": bson.M{"$gt": time.Now().Add(-240 * time.Hour)}}
	group := bson.M{"_id": bson.M{"event": "$what", "note": "$details.note"}, "count": bson.M{"$sum": 1}}

	err := coll.Pipe([]bson.M{{"$match": match}, {"$group": group}}).All(&qresults)
	if err != nil {
		return nil, errors.Wrap(err, "GetShardingChangelogStatus.changelog.find")
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

func parseFlags() (*options, error) {
	opts := &options{
		Host:               DEFAULT_HOST,
		LogLevel:           DEFAULT_LOGLEVEL,
		RunningOpsSamples:  DEFAULT_RUNNINGOPSSAMPLES,
		RunningOpsInterval: DEFAULT_RUNNINGOPSINTERVAL, // milliseconds
		AuthDB:             DEFAULT_AUTHDB,
	}

	gop := getopt.New()
	gop.BoolVarLong(&opts.Help, "help", 'h', "Show help")
	gop.BoolVarLong(&opts.Version, "version", 'v', "", "Show version & exit")
	gop.BoolVarLong(&opts.NoVersionCheck, "no-version-check", 'c', "", "Default: Don't check for updates")

	gop.StringVarLong(&opts.User, "username", 'u', "", "Username to use for optional MongoDB authentication")
	gop.StringVarLong(&opts.Password, "password", 'p', "", "Password to use for optional MongoDB authentication").SetOptional()
	gop.StringVarLong(&opts.AuthDB, "authenticationDatabase", 'a', "admin",
		"Databaae to use for optional MongoDB authentication. Default: admin")
	gop.StringVarLong(&opts.LogLevel, "log-level", 'l', "error", "Log level: panic, fatal, error, warn, info, debug. Default: error")

	gop.IntVarLong(&opts.RunningOpsSamples, "running-ops-samples", 's',
		fmt.Sprintf("Number of samples to collect for running ops. Default: %d", opts.RunningOpsSamples))

	gop.IntVarLong(&opts.RunningOpsInterval, "running-ops-interval", 'i',
		fmt.Sprintf("Interval to wait betwwen running ops samples in milliseconds. Default %d milliseconds", opts.RunningOpsInterval))

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
	if opts.Help {
		gop.PrintUsage(os.Stdout)
		return nil, nil
	}

	return opts, nil
}

func getChunksCount(session pmgo.SessionManager) ([]proto.ChunksByCollection, error) {
	var result []proto.ChunksByCollection

	c := session.DB("config").C("chunks")
	query := bson.M{"$group": bson.M{"_id": "$ns", "count": bson.M{"$sum": 1}}}

	// db.getSiblingDB('config').chunks.aggregate({$group:{_id:"$ns",count:{$sum:1}}})
	err := c.Pipe([]bson.M{query}).All(&result)
	if err != nil {
		return nil, err
	}
	return result, nil
}
