package main

import (
	"fmt"
	"html/template"
	"log"
	"os"
	"strings"
	"time"

	"github.com/howeyc/gopass"
	"github.com/pborman/getopt"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-summary/templates"
	"github.com/percona/pmgo"
	"github.com/pkg/errors"
	"github.com/shirou/gopsutil/process"
	"gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
)

var (
	Version string
	Build   string
)

type hostInfo struct {
	ThisHostID        int
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
	Users int
	Roles int
	Auth  string
	SSL   string
}

type timedStats struct {
	Min   int64
	Max   int64
	Total int64
	Avg   int64
}

type opCounters struct {
	Insert     timedStats
	Query      timedStats
	Update     timedStats
	Delete     timedStats
	GetMore    timedStats
	Command    timedStats
	SampleRate time.Duration
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
}

type options struct {
	Host     string
	User     string
	Password string
	AuthDB   string
	Debug    bool
	Version  bool
}

func main() {

	opts := options{Host: "localhost:27017"}
	help := getopt.BoolLong("help", '?', "Show help")
	getopt.BoolVarLong(&opts.Version, "version", 'v', "", "show version & exit")

	getopt.StringVarLong(&opts.User, "user", 'u', "", "username")
	getopt.StringVarLong(&opts.Password, "password", 'p', "", "password").SetOptional()
	getopt.StringVarLong(&opts.AuthDB, "authenticationDatabase", 'a', "admin", "database used to establish credentials and privileges with a MongoDB server")
	getopt.SetParameters("host[:port]")

	getopt.Parse()
	if *help {
		getopt.Usage()
		return
	}

	args := getopt.Args() // positional arg
	if len(args) > 0 {
		opts.Host = args[0]
	}

	if opts.Version {
		fmt.Println("pt-mongodb-summary")
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s\n", Build)
		return
	}

	if getopt.IsSet("password") && opts.Password == "" {
		print("Password: ")
		pass, err := gopass.GetPasswd()
		if err != nil {
			fmt.Println(err)
			os.Exit(2)
		}
		opts.Password = string(pass)
	}

	di := &mgo.DialInfo{
		Username: opts.User,
		Password: opts.Password,
		Addrs:    []string{opts.Host},
		FailFast: true,
		Source:   opts.AuthDB,
	}

	dialer := pmgo.NewDialer()

	hostnames, err := getHostnames(dialer, di)

	session, err := dialer.DialWithInfo(di)
	if err != nil {
		log.Printf("cannot connect to the db: %s", err)
		os.Exit(1)
	}
	defer session.Close()

	if replicaMembers, err := GetReplicasetMembers(dialer, hostnames, di); err != nil {
		log.Printf("[Error] cannot get replicaset members: %v\n", err)
	} else {
		t := template.Must(template.New("replicas").Parse(templates.Replicas))
		t.Execute(os.Stdout, replicaMembers)
	}

	//
	if hostInfo, err := GetHostinfo(session); err != nil {
		log.Printf("[Error] cannot get host info: %v\n", err)
	} else {
		t := template.Must(template.New("hosttemplateData").Parse(templates.HostInfo))
		t.Execute(os.Stdout, hostInfo)
	}

	var sampleCount int64 = 5
	var sampleRate time.Duration = 1 // in seconds
	if rops, err := GetOpCountersStats(session, sampleCount, sampleRate); err != nil {
		log.Printf("[Error] cannot get Opcounters stats: %v\n", err)
	} else {
		t := template.Must(template.New("runningOps").Parse(templates.RunningOps))
		t.Execute(os.Stdout, rops)
	}

	if security, err := GetSecuritySettings(session); err != nil {
		log.Printf("[Error] cannot get security settings: %v\n", err)
	} else {
		t := template.Must(template.New("ssl").Parse(templates.Security))
		t.Execute(os.Stdout, security)
	}

	if oplogInfo, err := GetOplogInfo(hostnames, di); err != nil {
		log.Printf("[Error] cannot get Oplog info: %v\n", err)
	} else {
		if len(oplogInfo) > 0 {
			t := template.Must(template.New("oplogInfo").Parse(templates.Oplog))
			t.Execute(os.Stdout, oplogInfo[0])
		}
	}

	if cwi, err := GetClusterwideInfo(session); err != nil {
		log.Printf("[Error] cannot get cluster wide info: %v\n", err)
	} else {
		t := template.Must(template.New("clusterwide").Parse(templates.Clusterwide))
		t.Execute(os.Stdout, cwi)
	}

	if bs, err := GetBalancerStats(session); err != nil {
		log.Printf("[Error] cannot get balancer stats: %v\n", err)
	} else {
		t := template.Must(template.New("balancer").Parse(templates.BalancerStats))
		t.Execute(os.Stdout, bs)
	}

}

func GetHostinfo2(session pmgo.SessionManager) (*hostInfo, error) {

	hi := proto.HostInfo{}
	if err := session.Run(bson.M{"hostInfo": 1}, &hi); err != nil {
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

	i := &hostInfo{
		Hostname:          hi.System.Hostname,
		HostOsType:        hi.Os.Type,
		HostSystemCPUArch: hi.System.CpuArch,
		HostDatabases:     hi.DatabasesCount,
		HostCollections:   hi.CollectionsCount,
		DBPath:            "", // Sets default. It will be overriden later if necessary

		ProcessName: ss.Process,
		Version:     ss.Version,
		NodeType:    nodeType,

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
func GetHostinfo(session pmgo.SessionManager) (*hostInfo, error) {

	hi := proto.HostInfo{}
	if err := session.Run(bson.M{"hostInfo": 1}, &hi); err != nil {
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

	i := &hostInfo{
		Hostname:          hi.System.Hostname,
		HostOsType:        hi.Os.Type,
		HostSystemCPUArch: hi.System.CpuArch,
		HostDatabases:     hi.DatabasesCount,
		HostCollections:   hi.CollectionsCount,
		DBPath:            "", // Sets default. It will be overriden later if necessary

		ProcessName: ss.Process,
		Version:     ss.Version,
		NodeType:    nodeType,

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

func getHostnames(dialer pmgo.Dialer, di *mgo.DialInfo) ([]string, error) {

	session, err := dialer.DialWithInfo(di)
	if err != nil {
		return nil, err
	}
	defer session.Close()

	shardsInfo := &proto.ShardsInfo{}
	err = session.Run("listShards", shardsInfo)
	if err != nil {
		return nil, errors.Wrap(err, "cannot list shards")
	}

	hostnames := []string{di.Addrs[0]}
	if shardsInfo != nil {
		for _, shardInfo := range shardsInfo.Shards {
			m := strings.Split(shardInfo.Host, "/")
			h := strings.Split(m[1], ",")
			hostnames = append(hostnames, h[0])
		}
	}
	return hostnames, nil
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

	configDB := session.DB("config")

	for _, db := range databases.Databases {
		collections, err := session.DB(db.Name).CollectionNames()
		if err != nil {
			continue
		}
		cwi.TotalCollectionsCount += len(collections)
		if len(db.Shards) == 1 {
			cwi.UnshardedDataSize += db.SizeOnDisk
			continue
		}
		cwi.ShardedDataSize += db.SizeOnDisk
		colsCount, _ := configDB.C("collections").Find(bson.M{"_id": bson.RegEx{"^" + db.Name, ""}}).Count()
		cwi.ShardedColsCount += colsCount
	}

	cwi.UnshardedColsCount = cwi.TotalCollectionsCount - cwi.ShardedColsCount
	cwi.ShardedDataSizeScaled, cwi.ShardedDataSizeScale = sizeAndUnit(cwi.ShardedDataSize)
	cwi.UnshardedDataSizeScaled, cwi.UnshardedDataSizeScale = sizeAndUnit(cwi.UnshardedDataSize)

	return cwi, nil
}

func sizeAndUnit(size int64) (float64, string) {
	unit := []string{"KB", "MB", "GB", "TB"}
	idx := 0
	newSize := float64(size)
	for newSize > 1024 {
		newSize /= 1024
		idx++
	}
	newSize = float64(int64(newSize*100) / 1000)
	return newSize, unit[idx]
}

func GetReplicasetMembers(dialer pmgo.Dialer, hostnames []string, di *mgo.DialInfo) ([]proto.Members, error) {
	replicaMembers := []proto.Members{}

	for _, hostname := range hostnames {
		di.Addrs = []string{hostname}
		session, err := dialer.DialWithInfo(di)
		if err != nil {
			return nil, errors.Wrapf(err, "getReplicasetMembers. cannot connect to %s", hostname)
		}
		defer session.Close()

		rss := proto.ReplicaSetStatus{}
		err = session.Run(bson.M{"replSetGetStatus": 1}, &rss)
		if err != nil {
			continue // If a host is a mongos we cannot get info but is not a real error
		}
		for _, m := range rss.Members {
			m.Set = rss.Set
			replicaMembers = append(replicaMembers, m)
		}
	}

	return replicaMembers, nil
}

func GetSecuritySettings(session pmgo.SessionManager) (*security, error) {
	s := security{
		Auth: "disabled",
		SSL:  "disabled",
	}

	cmdOpts := proto.CommandLineOptions{}
	err := session.DB("admin").Run(bson.D{{"getCmdLineOpts", 1}, {"recordStats", 1}}, &cmdOpts)
	if err != nil {
		return nil, errors.Wrap(err, "cannot get command line options")
	}

	if cmdOpts.Security.Authorization != "" || cmdOpts.Security.KeyFile != "" {
		s.Auth = "enabled"
	}
	if cmdOpts.Parsed.Net.SSL.Mode != "" && cmdOpts.Parsed.Net.SSL.Mode != "disabled" {
		s.SSL = cmdOpts.Parsed.Net.SSL.Mode
	}

	s.Users, err = session.DB("admin").C("system.users").Count()
	if err != nil {
		return nil, errors.Wrap(err, "cannot get users count")
	}

	s.Roles, err = session.DB("admin").C("system.roles").Count()
	if err != nil {
		return nil, errors.Wrap(err, "cannot get roles count")
	}

	return &s, nil
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

func GetOpCountersStats(session pmgo.SessionManager, count int64, sleep time.Duration) (*opCounters, error) {
	oc := &opCounters{}
	ss := proto.ServerStatus{}

	err := session.DB("admin").Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, &ss)
	if err != nil {
		return nil, errors.Wrap(err, "GetOpCountersStats.ServerStatus")
	}

	ticker := time.NewTicker(sleep)
	for i := int64(0); i < count-1; i++ {
		<-ticker.C
		err := session.DB("admin").Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, &ss)
		if err != nil {
			continue
		}
		// Insert
		if ss.Opcounters.Insert > oc.Insert.Max {
			oc.Insert.Max = ss.Opcounters.Insert
		}
		if ss.Opcounters.Insert < oc.Insert.Min {
			oc.Insert.Min = ss.Opcounters.Insert
		}
		oc.Insert.Total += ss.Opcounters.Insert

		// Query ---------------------------------------
		if ss.Opcounters.Query > oc.Query.Max {
			oc.Query.Max = ss.Opcounters.Query
		}
		if ss.Opcounters.Query < oc.Query.Min {
			oc.Query.Min = ss.Opcounters.Query
		}
		oc.Query.Total += ss.Opcounters.Query

		// Command -------------------------------------
		if ss.Opcounters.Command > oc.Command.Max {
			oc.Command.Max = ss.Opcounters.Command
		}
		if ss.Opcounters.Command < oc.Command.Min {
			oc.Command.Min = ss.Opcounters.Command
		}
		oc.Command.Total += ss.Opcounters.Command

		// Update --------------------------------------
		if ss.Opcounters.Update > oc.Update.Max {
			oc.Update.Max = ss.Opcounters.Update
		}
		if ss.Opcounters.Update < oc.Update.Min {
			oc.Update.Min = ss.Opcounters.Update
		}
		oc.Update.Total += ss.Opcounters.Update

		// Delete --------------------------------------
		if ss.Opcounters.Delete > oc.Delete.Max {
			oc.Delete.Max = ss.Opcounters.Delete
		}
		if ss.Opcounters.Delete < oc.Delete.Min {
			oc.Delete.Min = ss.Opcounters.Delete
		}
		oc.Delete.Total += ss.Opcounters.Delete

		// GetMore -------------------------------------
		if ss.Opcounters.GetMore > oc.GetMore.Max {
			oc.GetMore.Max = ss.Opcounters.GetMore
		}
		if ss.Opcounters.GetMore < oc.GetMore.Min {
			oc.GetMore.Min = ss.Opcounters.GetMore
		}
		oc.GetMore.Total += ss.Opcounters.GetMore
	}
	ticker.Stop()

	oc.Insert.Avg = oc.Insert.Total / count
	oc.Query.Avg = oc.Query.Total / count
	oc.Update.Avg = oc.Update.Total / count
	oc.Delete.Avg = oc.Delete.Total / count
	oc.GetMore.Avg = oc.GetMore.Total / count
	oc.Command.Avg = oc.Command.Total / count
	//
	oc.SampleRate = time.Duration(count) * time.Second * sleep

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
