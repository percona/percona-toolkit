package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"text/template"
	"time"

	"github.com/howeyc/gopass"
	"github.com/pborman/getopt"
	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/profiler"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
	"github.com/percona/pmgo"
	log "github.com/sirupsen/logrus"
	"gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
)

const (
	TOOLNAME = "pt-mongodb-query-digest"

	DEFAULT_AUTHDB          = "admin"
	DEFAULT_HOST            = "localhost:27017"
	DEFAULT_LOGLEVEL        = "warn"
	DEFAULT_ORDERBY         = "-count"         // comma separated list
	DEFAULT_SKIPCOLLECTIONS = "system.profile" // comma separated list
)

var (
	Build     string = "01-01-1980"
	GoVersion string = "1.8"
	Version   string = "3.0.3"
)

type options struct {
	AuthDB          string
	Database        string
	Debug           bool
	Help            bool
	Host            string
	Limit           int
	LogLevel        string
	NoVersionCheck  bool
	OrderBy         []string
	Password        string
	SkipCollections []string
	SSLCAFile       string
	SSLPEMKeyFile   string
	User            string
	Version         bool
}

func main() {

	opts, err := getOptions()
	if err != nil {
		log.Errorf("error processing commad line arguments: %s", err)
		os.Exit(1)
	}
	if opts == nil && err == nil {
		return
	}

	logLevel, err := log.ParseLevel(opts.LogLevel)
	if err != nil {
		fmt.Printf("Cannot set log level: %s", err.Error())
		os.Exit(1)
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
				log.Warn(advice)
			}
		}
	}

	di := getDialInfo(opts)
	if di.Database == "" {
		log.Errorln("must indicate a database as host:[port]/database")
		getopt.PrintUsage(os.Stderr)
		os.Exit(2)
	}

	dialer := pmgo.NewDialer()
	session, err := dialer.DialWithInfo(di)
	if err != nil {
		log.Errorf("Error connecting to the db: %s while trying to connect to %s", err, di.Addrs[0])
		os.Exit(3)
	}

	isProfilerEnabled, err := isProfilerEnabled(dialer, di)
	if err != nil {
		log.Errorf("Cannot get profiler status: %s", err.Error())
		os.Exit(4)
	}

	if !isProfilerEnabled {
		count, err := systemProfileDocsCount(session, di.Database)
		if err != nil || count == 0 {
			log.Error("Profiler is not enabled")
			os.Exit(5)
		}
		fmt.Printf("Profiler is disabled for the %q database but there are %d documents in the system.profile collection.\n",
			di.Database, count)
		fmt.Println("Using those documents for the stats")
	}

	opts.SkipCollections = sanitizeSkipCollections(opts.SkipCollections)
	filters := []filter.Filter{}

	if len(opts.SkipCollections) > 0 {
		filters = append(filters, filter.NewFilterByCollection(opts.SkipCollections))
	}

	query := bson.M{"op": bson.M{"$nin": []string{"getmore", "delete"}}}
	i := session.DB(di.Database).C("system.profile").Find(query).Sort("-$natural").Iter()

	fp := fingerprinter.NewFingerprinter(fingerprinter.DEFAULT_KEY_FILTERS)
	s := stats.New(fp)
	prof := profiler.NewProfiler(i, filters, nil, s)
	prof.Start()
	queries := <-prof.QueriesChan()

	uptime := uptime(session)

	queriesStats := queries.CalcQueriesStats(uptime)
	sortedQueryStats := sortQueries(queriesStats, opts.OrderBy)

	printHeader(opts)

	queryTotals := queries.CalcTotalQueriesStats(uptime)
	tt, _ := template.New("query").Funcs(template.FuncMap{
		"Format": format,
	}).Parse(getTotalsTemplate())
	tt.Execute(os.Stdout, queryTotals)

	t, _ := template.New("query").Funcs(template.FuncMap{
		"Format": format,
	}).Parse(getQueryTemplate())

	if opts.Limit > 0 && len(sortedQueryStats) > opts.Limit {
		sortedQueryStats = sortedQueryStats[:opts.Limit]
	}
	for _, qs := range sortedQueryStats {
		t.Execute(os.Stdout, qs)
	}

}

// format scales a number and returns a string made of the scaled value and unit (K=Kilo, M=Mega, T=Tera)
// using I.F where i is the number of digits for the integer part and F is the number of digits for the
// decimal part
// Examples:
// format(1000, 5.0) will return 1K
// format(1000, 5.2) will return 1.00k
func format(val float64, size float64) string {
	units := []string{"K", "M", "T"}
	unit := " "
	intSize := int64(size)
	decSize := int64((size - float64(intSize)) * 10)
	for i := 0; i < 3; i++ {
		if val > 1000 {
			val /= 1000
			unit = units[i]
		}
	}

	pfmt := fmt.Sprintf("%% %d.%df", intSize, decSize)
	fval := fmt.Sprintf(pfmt, val)

	return fmt.Sprintf("%s%s", fval, unit)
}

func uptime(session pmgo.SessionManager) int64 {
	ss := proto.ServerStatus{}
	if err := session.Ping(); err != nil {
		return 0
	}

	if err := session.DB("admin").Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, &ss); err != nil {
		return 0
	}
	return ss.Uptime
}

func getOptions() (*options, error) {
	opts := &options{
		Host:            DEFAULT_HOST,
		LogLevel:        DEFAULT_LOGLEVEL,
		OrderBy:         strings.Split(DEFAULT_ORDERBY, ","),
		SkipCollections: strings.Split(DEFAULT_SKIPCOLLECTIONS, ","),
		AuthDB:          DEFAULT_AUTHDB,
	}

	gop := getopt.New()
	gop.BoolVarLong(&opts.Help, "help", '?', "Show help")
	gop.BoolVarLong(&opts.Version, "version", 'v', "Show version & exit")
	gop.BoolVarLong(&opts.NoVersionCheck, "no-version-check", 'c', "Default: Don't check for updates")

	gop.IntVarLong(&opts.Limit, "limit", 'n', "Show the first n queries")

	gop.ListVarLong(&opts.OrderBy, "order-by", 'o',
		"Comma separated list of order by fields (max values): "+
			"count,ratio,query-time,docs-scanned,docs-returned. "+
			"- in front of the field name denotes reverse order. Default: "+DEFAULT_ORDERBY)
	gop.ListVarLong(&opts.SkipCollections, "skip-collections", 's', "A comma separated list of collections (namespaces) to skip."+
		"  Default: "+DEFAULT_SKIPCOLLECTIONS)

	gop.StringVarLong(&opts.AuthDB, "authenticationDatabase", 'a', "admin", "Database to use for optional MongoDB authentication. Default: admin")
	gop.StringVarLong(&opts.Database, "database", 'd', "", "MongoDB database to profile")
	gop.StringVarLong(&opts.LogLevel, "log-level", 'l', "Log level: error", "panic, fatal, error, warn, info, debug. Default: error")
	gop.StringVarLong(&opts.Password, "password", 'p', "", "Password to use for optional MongoDB authentication").SetOptional()
	gop.StringVarLong(&opts.User, "username", 'u', "Username to use for optional MongoDB authentication")
	gop.StringVarLong(&opts.SSLCAFile, "sslCAFile", 0, "SSL CA cert file used for authentication")
	gop.StringVarLong(&opts.SSLPEMKeyFile, "sslPEMKeyFile", 0, "SSL client PEM file used for authentication")

	gop.SetParameters("host[:port]/database")

	gop.Parse(os.Args)
	if gop.NArgs() > 0 {
		opts.Host = gop.Arg(0)
		gop.Parse(gop.Args())
	}
	if opts.Help {
		gop.PrintUsage(os.Stdout)
		return nil, nil
	}

	if gop.IsSet("order-by") {
		validFields := []string{"count", "ratio", "query-time", "docs-scanned", "docs-returned"}
		for _, field := range opts.OrderBy {
			valid := false
			for _, vf := range validFields {
				if field == vf || field == "-"+vf {
					valid = true
				}
			}
			if !valid {
				return nil, fmt.Errorf("invalid sort field '%q'", field)
			}
		}
	}

	if gop.IsSet("password") && opts.Password == "" {
		print("Password: ")
		pass, err := gopass.GetPasswd()
		if err != nil {
			return nil, err
		}
		opts.Password = string(pass)
	}

	return opts, nil
}

func getDialInfo(opts *options) *pmgo.DialInfo {
	di, _ := mgo.ParseURL(opts.Host)
	di.FailFast = true

	if di.Username != "" {
		di.Username = opts.User
	}
	if di.Password != "" {
		di.Password = opts.Password
	}
	if opts.AuthDB != "" {
		di.Source = opts.AuthDB
	}
	if opts.Database != "" {
		di.Database = opts.Database
	}

	pmgoDialInfo := pmgo.NewDialInfo(di)

	if opts.SSLCAFile != "" {
		pmgoDialInfo.SSLCAFile = opts.SSLCAFile
	}

	if opts.SSLPEMKeyFile != "" {
		pmgoDialInfo.SSLPEMKeyFile = opts.SSLPEMKeyFile
	}

	return pmgoDialInfo
}

func printHeader(opts *options) {
	fmt.Printf("%s - %s\n", TOOLNAME, time.Now().Format(time.RFC1123Z))
	fmt.Printf("Host: %s\n", opts.Host)
	fmt.Printf("Skipping profiled queries on these collections: %v\n", opts.SkipCollections)
	fmt.Println("")
}

func getQueryTemplate() string {

	t := `
# Query {{.Rank}}: {{printf "% 0.2f" .QPS}} QPS, ID {{.ID}}
# Ratio {{Format .Ratio 7.2}} (docs scanned/returned)
# Time range: {{.FirstSeen}} to {{.LastSeen}}
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count (docs)               {{printf "% 7d " .Count}}
# Exec Time ms        {{printf "% 4.0f" .QueryTime.Pct}}   {{printf "% 7.0f " .QueryTime.Total}}    {{printf "% 7.0f " .QueryTime.Min}}    {{printf "% 7.0f " .QueryTime.Max}}    {{printf "% 7.0f " .QueryTime.Avg}}    {{printf "% 7.0f " .QueryTime.Pct95}}    {{printf "% 7.0f " .QueryTime.StdDev}}    {{printf "% 7.0f " .QueryTime.Median}}
# Docs Scanned        {{printf "% 4.0f" .Scanned.Pct}}   {{Format .Scanned.Total 7.2}}    {{Format .Scanned.Min 7.2}}    {{Format .Scanned.Max 7.2}}    {{Format .Scanned.Avg 7.2}}    {{Format .Scanned.Pct95 7.2}}    {{Format .Scanned.StdDev 7.2}}    {{Format .Scanned.Median 7.2}}
# Docs Returned       {{printf "% 4.0f" .Returned.Pct}}   {{Format .Returned.Total 7.2}}    {{Format .Returned.Min 7.2}}    {{Format .Returned.Max 7.2}}    {{Format .Returned.Avg 7.2}}    {{Format .Returned.Pct95 7.2}}    {{Format .Returned.StdDev 7.2}}    {{Format .Returned.Median 7.2}}
# Bytes recv          {{printf "% 4.0f" .ResponseLength.Pct}}   {{Format .ResponseLength.Total 7.2}}    {{Format .ResponseLength.Min 7.2}}    {{Format .ResponseLength.Max 7.2}}    {{Format .ResponseLength.Avg 7.2}}    {{Format .ResponseLength.Pct95 7.2}}    {{Format .ResponseLength.StdDev 7.2}}    {{Format .ResponseLength.Median 7.2}}
# String:
# Namespaces          {{.Namespace}}
# Operation           {{.Operation}}
# Fingerprint         {{.Fingerprint}}
# Query               {{.Query}}
`
	return t
}

func getTotalsTemplate() string {
	t := `
# Totals
# Ratio {{Format .Ratio 7.2}} (docs scanned/returned)
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count (docs)               {{printf "% 7d " .Count}}
# Exec Time ms        {{printf "% 4.0f" .QueryTime.Pct}}   {{printf "% 7.0f " .QueryTime.Total}}    {{printf "% 7.0f " .QueryTime.Min}}    {{printf "% 7.0f " .QueryTime.Max}}    {{printf "% 7.0f " .QueryTime.Avg}}    {{printf "% 7.0f " .QueryTime.Pct95}}    {{printf "% 7.0f " .QueryTime.StdDev}}    {{printf "% 7.0f " .QueryTime.Median}}
# Docs Scanned        {{printf "% 4.0f" .Scanned.Pct}}   {{Format .Scanned.Total 7.2}}    {{Format .Scanned.Min 7.2}}    {{Format .Scanned.Max 7.2}}    {{Format .Scanned.Avg 7.2}}    {{Format .Scanned.Pct95 7.2}}    {{Format .Scanned.StdDev 7.2}}    {{Format .Scanned.Median 7.2}}
# Docs Returned       {{printf "% 4.0f" .Returned.Pct}}   {{Format .Returned.Total 7.2}}    {{Format .Returned.Min 7.2}}    {{Format .Returned.Max 7.2}}    {{Format .Returned.Avg 7.2}}    {{Format .Returned.Pct95 7.2}}    {{Format .Returned.StdDev 7.2}}    {{Format .Returned.Median 7.2}}
# Bytes recv          {{printf "% 4.0f" .ResponseLength.Pct}}   {{Format .ResponseLength.Total 7.2}}    {{Format .ResponseLength.Min 7.2}}    {{Format .ResponseLength.Max 7.2}}    {{Format .ResponseLength.Avg 7.2}}    {{Format .ResponseLength.Pct95 7.2}}    {{Format .ResponseLength.StdDev 7.2}}    {{Format .ResponseLength.Median 7.2}}
# 
`
	return t
}

type lessFunc func(p1, p2 *stats.QueryStats) bool

type multiSorter struct {
	queries []stats.QueryStats
	less    []lessFunc
}

// Sort sorts the argument slice according to the less functions passed to OrderedBy.
func (ms *multiSorter) Sort(queries []stats.QueryStats) {
	ms.queries = queries
	sort.Sort(ms)
}

// OrderedBy returns a Sorter that sorts using the less functions, in order.
// Call its Sort method to sort the data.
func OrderedBy(less ...lessFunc) *multiSorter {
	return &multiSorter{
		less: less,
	}
}

// Len is part of sort.Interface.
func (ms *multiSorter) Len() int {
	return len(ms.queries)
}

// Swap is part of sort.Interface.
func (ms *multiSorter) Swap(i, j int) {
	ms.queries[i], ms.queries[j] = ms.queries[j], ms.queries[i]
}

// Less is part of sort.Interface. It is implemented by looping along the
// less functions until it finds a comparison that is either Less or
// !Less. Note that it can call the less functions twice per call. We
// could change the functions to return -1, 0, 1 and reduce the
// number of calls for greater efficiency: an exercise for the reader.
func (ms *multiSorter) Less(i, j int) bool {
	p, q := &ms.queries[i], &ms.queries[j]
	// Try all but the last comparison.
	var k int
	for k = 0; k < len(ms.less)-1; k++ {
		less := ms.less[k]
		switch {
		case less(p, q):
			// p < q, so we have a decision.
			return true
		case less(q, p):
			// p > q, so we have a decision.
			return false
		}
		// p == q; try the next comparison.
	}
	// All comparisons to here said "equal", so just return whatever
	// the final comparison reports.
	return ms.less[k](p, q)
}

func sortQueries(queries []stats.QueryStats, orderby []string) []stats.QueryStats {
	sortFuncs := []lessFunc{}
	for _, field := range orderby {
		var f lessFunc
		switch field {
		//
		case "count":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Count < c2.Count
			}
		case "-count":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Count > c2.Count
			}

		case "ratio":
			f = func(c1, c2 *stats.QueryStats) bool {
				ratio1 := c1.Scanned.Max / c1.Returned.Max
				ratio2 := c2.Scanned.Max / c2.Returned.Max
				return ratio1 < ratio2
			}
		case "-ratio":
			f = func(c1, c2 *stats.QueryStats) bool {
				ratio1 := c1.Scanned.Max / c1.Returned.Max
				ratio2 := c2.Scanned.Max / c2.Returned.Max
				return ratio1 > ratio2
			}

		//
		case "query-time":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.QueryTime.Max < c2.QueryTime.Max
			}
		case "-query-time":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.QueryTime.Max > c2.QueryTime.Max
			}

		//
		case "docs-scanned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Scanned.Max < c2.Scanned.Max
			}
		case "-docs-scanned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Scanned.Max > c2.Scanned.Max
			}

		//
		case "docs-returned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Returned.Max < c2.Scanned.Max
			}
		case "-docs-returned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Returned.Max > c2.Scanned.Max
			}
		}
		// count,query-time,docs-scanned, docs-returned. - in front of the field name denotes reverse order.")
		sortFuncs = append(sortFuncs, f)
	}

	OrderedBy(sortFuncs...).Sort(queries)
	return queries

}

func isProfilerEnabled(dialer pmgo.Dialer, di *pmgo.DialInfo) (bool, error) {
	var ps proto.ProfilerStatus
	replicaMembers, err := util.GetReplicasetMembers(dialer, di)
	if err != nil {
		return false, err
	}

	for _, member := range replicaMembers {
		// Stand alone instances return state = REPLICA_SET_MEMBER_STARTUP
		di.Addrs = []string{member.Name}
		session, err := dialer.DialWithInfo(di)
		if err != nil {
			continue
		}
		defer session.Close()
		session.SetMode(mgo.Monotonic, true)

		isReplicaEnabled := isReplicasetEnabled(session)

		if strings.ToLower(member.StateStr) == "configsvr" {
			continue
		}

		if isReplicaEnabled && member.State != proto.REPLICA_SET_MEMBER_PRIMARY {
			continue
		}
		if err := session.DB(di.Database).Run(bson.M{"profile": -1}, &ps); err != nil {
			continue
		}

		if ps.Was == 0 {
			return false, nil
		}
	}
	return true, nil
}

func systemProfileDocsCount(session pmgo.SessionManager, dbname string) (int, error) {
	return session.DB(dbname).C("system.profile").Count()
}

func isReplicasetEnabled(session pmgo.SessionManager) bool {
	rss := proto.ReplicaSetStatus{}
	if err := session.Run(bson.M{"replSetGetStatus": 1}, &rss); err != nil {
		return false
	}
	return true
}

// Sanitize the param. using --skip-collections="" will produce an 1 element array but
// that element will be empty. The same would be using --skip-collections=a,,d
func sanitizeSkipCollections(skipCollections []string) []string {
	cols := []string{}
	if len(skipCollections) > 0 {
		for _, c := range skipCollections {
			if strings.TrimSpace(c) != "" {
				cols = append(cols, c)
			}
		}
	}
	return cols
}
