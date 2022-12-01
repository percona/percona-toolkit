package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"text/template"
	"time"

	"github.com/howeyc/gopass"
	"github.com/pborman/getopt"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/profiler"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/stats"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-query-digest/filter"
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
	Build     string = "2020-04-23" //nolint
	GoVersion string = "1.14.1"     //nolint
	Version   string = "3.5.0"      //nolint
	Commit    string                //nolint
)

type cliOptions struct {
	AuthDB          string
	Database        string
	Debug           bool
	Help            bool
	Host            string
	Limit           int
	LogLevel        string
	NoVersionCheck  bool
	OrderBy         []string
	OutputFormat    string
	Password        string
	SkipCollections []string
	SSLCAFile       string
	SSLPEMKeyFile   string
	User            string
	Version         bool
}

type report struct {
	Headers     []string
	QueryStats  []stats.QueryStats
	QueryTotals stats.QueryStats
}

func main() {
	opts, err := getOptions()
	if err != nil {
		log.Errorf("error processing command line arguments: %s", err)
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
		fmt.Printf("Commit: %s\n", Commit)
		return
	}

	conf := config.DefaultConfig(TOOLNAME)
	if !conf.GetBool("no-version-check") && !opts.NoVersionCheck {
		advice, err := versioncheck.CheckUpdates(TOOLNAME, Version)
		if err != nil {
			log.Infof("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Warn(advice)
		}
	}

	log.Debugf("Command line options:\n%+v\n", opts)

	clientOptions, err := getClientOptions(opts)
	if err != nil {
		log.Errorf("Cannot get a MongoDB client: %s", err)
		os.Exit(2)
	}

	if opts.Database == "" {
		log.Errorln("must indicate a database to profile with the --database parameter")
		getopt.PrintUsage(os.Stderr)
		os.Exit(2)
	}

	ctx := context.Background()

	log.Debugf("Dial Info: %+v\n", clientOptions)

	client, err := mongo.NewClient(clientOptions)
	if err != nil {
		log.Fatalf("Cannot create a new MongoDB client: %s", err)
	}

	if err := client.Connect(ctx); err != nil {
		log.Fatalf("Cannot connect to MongoDB: %s", err)
	}

	isProfilerEnabled, err := isProfilerEnabled(ctx, clientOptions)
	if err != nil {
		log.Errorf("Cannot get profiler status: %s", err.Error())
		os.Exit(4)
	}

	if !isProfilerEnabled {
		count, err := systemProfileDocsCount(ctx, client, opts.Database)
		if err != nil || count == 0 {
			log.Error("Profiler is not enabled")
			os.Exit(5)
		}
		fmt.Printf("Profiler is disabled for the %q database but there are %d documents in the system.profile collection.\n",
			opts.Database, count)
		fmt.Println("Using those documents for the stats")
	}

	opts.SkipCollections = sanitizeSkipCollections(opts.SkipCollections)
	filters := []filter.Filter{}

	if len(opts.SkipCollections) > 0 {
		filters = append(filters, filter.NewFilterByCollection(opts.SkipCollections))
	}

	cursor, err := client.Database(opts.Database).Collection("system.profile").Find(ctx, primitive.M{})
	if err != nil {
		panic(err)
	}

	fp := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters())
	s := stats.New(fp)
	prof := profiler.NewProfiler(cursor, filters, nil, s)
	prof.Start(ctx)
	queries := <-prof.QueriesChan()

	uptime := uptime(ctx, client)

	queriesStats := queries.CalcQueriesStats(uptime)
	sortedQueryStats := sortQueries(queriesStats, opts.OrderBy)

	if opts.Limit > 0 && len(sortedQueryStats) > opts.Limit {
		sortedQueryStats = sortedQueryStats[:opts.Limit]
	}

	if len(queries) == 0 {
		log.Errorf("No queries found in profiler information for database %q\n", opts.Database)
		return
	}
	rep := report{
		Headers:     getHeaders(opts),
		QueryTotals: queries.CalcTotalQueriesStats(uptime),
		QueryStats:  sortedQueryStats,
	}

	out, err := formatResults(rep, opts.OutputFormat)
	if err != nil {
		log.Errorf("Cannot parse the report: %s", err.Error())
		os.Exit(5)
	}

	fmt.Println(string(out))
}

func formatResults(rep report, outputFormat string) ([]byte, error) {
	var buf *bytes.Buffer

	switch outputFormat {
	case "json":
		b, err := json.MarshalIndent(rep, "", "    ")
		if err != nil {
			return nil, fmt.Errorf("[Error] Cannot convert results to json: %s", err.Error())
		}
		buf = bytes.NewBuffer(b)
	default:
		buf = new(bytes.Buffer)

		tt, _ := template.New("query").Funcs(template.FuncMap{
			"Format": format,
		}).Parse(getTotalsTemplate())
		tt.Execute(buf, rep.QueryTotals)

		t, _ := template.New("query").Funcs(template.FuncMap{
			"Format": format,
		}).Parse(getQueryTemplate())

		for _, qs := range rep.QueryStats {
			t.Execute(buf, qs)
		}
	}

	return buf.Bytes(), nil
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

func uptime(ctx context.Context, client *mongo.Client) int64 {
	res := client.Database("admin").RunCommand(ctx, primitive.D{{"serverStatus", 1}, {"recordStats", 1}})
	if res.Err() != nil {
		return 0
	}
	ss := proto.ServerStatus{}
	if err := res.Decode(&ss); err != nil {
		return 0
	}
	return ss.Uptime
}

func getOptions() (*cliOptions, error) {
	opts := &cliOptions{
		Host:            DEFAULT_HOST,
		LogLevel:        DEFAULT_LOGLEVEL,
		OrderBy:         strings.Split(DEFAULT_ORDERBY, ","),
		SkipCollections: strings.Split(DEFAULT_SKIPCOLLECTIONS, ","),
		AuthDB:          DEFAULT_AUTHDB,
		OutputFormat:    "text",
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
	gop.StringVarLong(&opts.OutputFormat, "output-format", 'f', "text", "Output format: text, json. Default: text")
	gop.StringVarLong(&opts.Password, "password", 'p', "", "Password to use for optional MongoDB authentication").SetOptional()
	gop.StringVarLong(&opts.User, "username", 'u', "Username to use for optional MongoDB authentication")
	gop.StringVarLong(&opts.SSLCAFile, "sslCAFile", 0, "SSL CA cert file used for authentication")
	gop.StringVarLong(&opts.SSLPEMKeyFile, "sslPEMKeyFile", 0, "SSL client PEM file used for authentication")

	gop.SetParameters("host[:port]")

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

	if opts.OutputFormat != "json" && opts.OutputFormat != "text" {
		log.Infof("Invalid output format '%s'. Using text format", opts.OutputFormat)
		opts.OutputFormat = "text"
	}

	if gop.IsSet("password") && opts.Password == "" {
		print("Password: ")
		pass, err := gopass.GetPasswd()
		if err != nil {
			return nil, err
		}
		opts.Password = string(pass)
	}

	if !strings.HasPrefix(opts.Host, "mongodb://") {
		opts.Host = "mongodb://" + opts.Host
	}

	return opts, nil
}

func getClientOptions(opts *cliOptions) (*options.ClientOptions, error) {
	clientOptions := options.Client().ApplyURI(opts.Host)
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
	return clientOptions, nil
}

func getHeaders(opts *cliOptions) []string {
	h := []string{
		fmt.Sprintf("%s - %s\n", TOOLNAME, time.Now().Format(time.RFC1123Z)),
		fmt.Sprintf("Host: %s\n", opts.Host),
		fmt.Sprintf("Skipping profiled queries on these collections: %v\n", opts.SkipCollections),
	}
	return h
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
# Bytes sent          {{printf "% 4.0f" .ResponseLength.Pct}}   {{Format .ResponseLength.Total 7.2}}    {{Format .ResponseLength.Min 7.2}}    {{Format .ResponseLength.Max 7.2}}    {{Format .ResponseLength.Avg 7.2}}    {{Format .ResponseLength.Pct95 7.2}}    {{Format .ResponseLength.StdDev 7.2}}    {{Format .ResponseLength.Median 7.2}}
# String:
# Namespace           {{.Namespace}}
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
# Bytes sent          {{printf "% 4.0f" .ResponseLength.Pct}}   {{Format .ResponseLength.Total 7.2}}    {{Format .ResponseLength.Min 7.2}}    {{Format .ResponseLength.Max 7.2}}    {{Format .ResponseLength.Avg 7.2}}    {{Format .ResponseLength.Pct95 7.2}}    {{Format .ResponseLength.StdDev 7.2}}    {{Format .ResponseLength.Median 7.2}}
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
				return c1.Ratio < c2.Ratio
			}
		case "-ratio":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Ratio > c2.Ratio
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

func isProfilerEnabled(ctx context.Context, clientOptions *options.ClientOptions) (bool, error) {
	var ps proto.ProfilerStatus
	replicaMembers, err := util.GetReplicasetMembers(ctx, clientOptions)
	if err != nil {
		return false, err
	}

	for _, member := range replicaMembers {
		// Stand alone instances return state = REPLICA_SET_MEMBER_STARTUP
		client, err := util.GetClientForHost(clientOptions, member.Name)
		if err != nil {
			continue
		}

		isReplicaEnabled := isReplicasetEnabled(ctx, client)

		if strings.ToLower(member.StateStr) == "configsvr" {
			continue
		}

		if isReplicaEnabled && member.State != proto.REPLICA_SET_MEMBER_PRIMARY {
			continue
		}
		if err := client.Database("admin").RunCommand(ctx, primitive.M{"profile": -1}).Decode(&ps); err != nil {
			continue
		}

		if ps.Was == 0 {
			return false, nil
		}
	}
	return true, nil
}

func systemProfileDocsCount(ctx context.Context, client *mongo.Client, dbname string) (int64, error) {
	return client.Database(dbname).Collection("system.profile").CountDocuments(ctx, primitive.M{})
}

func isReplicasetEnabled(ctx context.Context, client *mongo.Client) bool {
	rss := proto.ReplicaSetStatus{}
	if err := client.Database("admin").RunCommand(ctx, primitive.M{"replSetGetStatus": 1}).Decode(&rss); err != nil {
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
