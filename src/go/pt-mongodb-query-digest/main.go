// This program is copyright 2017-2026 Percona LLC and/or its affiliates.
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
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"text/template"
	"time"

	"github.com/alecthomas/kong"
	"github.com/howeyc/gopass"
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
	toolname = "pt-mongodb-query-digest"

	DEFAULT_AUTHDB          = "admin"
	DEFAULT_HOST            = "localhost:27017"
	DEFAULT_LOGLEVEL        = "warn"
	DEFAULT_ORDERBY         = "-count"         // comma separated list
	DEFAULT_SKIPCOLLECTIONS = "system.profile" // comma separated list
)

// We do not set anything here, these variables are defined by the Makefile
var (
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint
)

type cliOptions struct {
	config.ConfigFlag
	AuthDB          string                    `name:"authenticationDatabase" short:"a" help:"Database to use for optional MongoDB authentication" default:"admin"`
	Database        string                    `name:"database" short:"d" help:"MongoDB database to profile"`
	Host            string                    `arg:"" name:"host" help:"host[:port]" default:"localhost:27017"`
	Limit           int                       `name:"limit" short:"n" help:"Show the first n queries"`
	LogLevel        string                    `name:"log-level" short:"l" help:"panic, fatal, error, warn, info, debug" default:"error"`
	OrderBy         []string                  `name:"order-by" short:"o" help:"Comma separated list of order by fields (count, ratio, query-time, docs-scanned, docs-returned). Prefix '-' for reverse order." default:"-count"`
	SkipCollections []string                  `name:"skip-collections" short:"s" help:"A comma separated list of collections (namespaces) to skip." default:"system.profile"`
	OutputFormat    string                    `name:"output-format" short:"f" help:"Output format: text, json." default:"text"`
	User            string                    `name:"username" short:"u" help:"Username to use for optional MongoDB authentication"`
	Password        config.StdinRequestString `name:"password" short:"p" help:"Password to use for optional MongoDB authentication"`
	SSLCAFile       string                    `name:"sslCAFile" help:"SSL CA cert file used for authentication"`
	SSLPEMKeyFile   string                    `name:"sslPEMKeyFile" help:"SSL client PEM file used for authentication"`
	config.VersionFlag
	config.VersionCheckFlag
}

func (c *cliOptions) AfterApply() error {
	if len(c.OrderBy) > 0 {
		validFields := []string{"count", "ratio", "query-time", "docs-scanned", "docs-returned"}
		for _, field := range c.OrderBy {
			valid := false
			for _, vf := range validFields {
				if field == vf || field == "-"+vf {
					valid = true
				}
			}
			if !valid {
				return fmt.Errorf("invalid sort field '%q'", field)
			}
		}
	}

	err := c.Password.Request(func() (string, error) {
		print("Password: ")
		pass, err := gopass.GetPasswd()
		return string(pass), err
	})
	if err != nil {
		return err
	}

	if c.OutputFormat != "json" && c.OutputFormat != "text" {
		log.Infof("Invalid output format '%s'. Using text format", c.OutputFormat)
		c.OutputFormat = "text"
	}

	if !strings.HasPrefix(c.Host, "mongodb://") {
		c.Host = "mongodb://" + c.Host
	}

	if c.Database == "" {
		return fmt.Errorf("must indicate a database to profile with the --database parameter")
	}

	logLevel, err := log.ParseLevel(c.LogLevel)
	if err != nil {
		return fmt.Errorf("Cannot set log level: %w", err)
	}
	log.SetLevel(logLevel)

	if c.VersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Errorf("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Infof("%s", advice)
		}
	}

	return nil
}

type report struct {
	Headers     []string
	QueryStats  []stats.QueryStats
	QueryTotals stats.QueryStats
}

func main() {
	var opts cliOptions
	_, _, err := config.Setup(
		toolname,
		&opts,
		kong.UsageOnError(),
		kong.Vars{
			"version": fmt.Sprintf(
				"%s\nVersion %s\nBuild: %s using %s\nCommit: %s",
				toolname, Version, Build, GoVersion, Commit,
			),
		},
	)
	if err != nil {
		log.Errorf("cannot get parameters: %s", err.Error())
		os.Exit(1)
	}

	if opts.Version {
		return
	}

	log.Debugf("Command line options:\n%+v\n", opts)

	clientOptions, err := getClientOptions(&opts)
	if err != nil {
		log.Errorf("Cannot get a MongoDB client: %s", err)
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

	isProfilerEnabled, err := isProfilerEnabled(ctx, clientOptions, opts.Database)
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
		Headers:     getHeaders(&opts),
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

func getClientOptions(opts *cliOptions) (*options.ClientOptions, error) {
	clientOptions := options.Client().ApplyURI(opts.Host)
	credential := options.Credential{}
	if opts.User != "" {
		credential.Username = opts.User
		clientOptions.SetAuth(credential)
	}
	if opts.Password != "" {
		credential.Password = string(opts.Password)
		credential.PasswordSet = true
		clientOptions.SetAuth(credential)
	}
	return clientOptions, nil
}

func getHeaders(opts *cliOptions) []string {
	h := []string{
		fmt.Sprintf("%s - %s\n", toolname, time.Now().Format(time.RFC1123Z)),
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

// Sort sorts the argument slice according to the less functions passed to orderedBy.
func (ms *multiSorter) Sort(queries []stats.QueryStats) {
	ms.queries = queries
	sort.Sort(ms)
}

// orderedBy returns a Sorter that sorts using the less functions, in order.
// Call its Sort method to sort the data.
func orderedBy(less ...lessFunc) *multiSorter {
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
		case "docs-examined":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.DocsExamined.Max < c2.DocsExamined.Max
			}
		case "-docs-examined":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.DocsExamined.Max > c2.DocsExamined.Max
			}

		//
		case "docs-returned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Returned.Max < c2.DocsExamined.Max
			}
		case "-docs-returned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Returned.Max > c2.DocsExamined.Max
			}
		}
		// count,query-time,docs-scanned, docs-returned. - in front of the field name denotes reverse order.")
		sortFuncs = append(sortFuncs, f)
	}

	orderedBy(sortFuncs...).Sort(queries)
	return queries
}

func isProfilerEnabled(ctx context.Context, clientOptions *options.ClientOptions, dbname string) (bool, error) {
	var ps proto.ProfilerStatus
	replicaMembers, err := util.GetReplicasetMembers(ctx, clientOptions)
	if err != nil && !errors.Is(err, util.ShardingNotEnabledError) {
		return false, err
	}

	if len(replicaMembers) == 0 {
		client, err := mongo.NewClient(clientOptions)
		if err != nil {
			return false, err
		}
		if err = client.Connect(ctx); err != nil {
			return false, err
		}

		client.Database(dbname).RunCommand(ctx, primitive.M{"profile": -1}).Decode(&ps)

		if ps.Was == 0 {
			return false, nil
		}
	}

	for _, member := range replicaMembers {
		client, err := util.GetClientForHost(clientOptions, member.Name)
		if err != nil {
			continue
		}
		if err := client.Connect(ctx); err != nil {
			log.Fatalf("Cannot connect to MongoDB: %s", err)
		}

		isReplicaEnabled := isReplicasetEnabled(ctx, client)

		if strings.ToLower(member.StateStr) == "configsvr" {
			continue
		}

		if isReplicaEnabled && member.State != proto.REPLICA_SET_MEMBER_PRIMARY {
			continue
		}
		if err := client.Database(dbname).RunCommand(ctx, primitive.M{"profile": -1}).Decode(&ps); err != nil {
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
