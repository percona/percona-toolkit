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
	"io"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"text/template"
	"time"

	"github.com/pborman/getopt"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"golang.org/x/term"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/mongolib/fingerprinter"
	"github.com/percona/percona-toolkit/src/go/mongolib/logparser"
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
	AuthDB          string
	Database        string
	Debug           bool
	Help            bool
	Host            string
	Limit           int
	LogFiles        []string
	LogLevel        string
	NoVersionCheck  bool
	OrderBy         []string
	OutputFormat    string
	Password        string
	ShowAll         []string
	Since           time.Time
	SkipCollections []string
	SSLCAFile       string
	SSLPEMKeyFile   string
	Until           time.Time
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
		fmt.Println(toolname)
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)
		return
	}

	conf := config.DefaultConfig(toolname)
	if !conf.GetBool("no-version-check") && !opts.NoVersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Infof("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Warn(advice)
		}
	}

	log.Debugf("Command line options:\n%+v\n", opts)

	opts.SkipCollections = sanitizeSkipCollections(opts.SkipCollections)

	var queries stats.Queries

	if len(opts.LogFiles) > 0 {
		queries, err = queriesFromLogs(opts)
		if err != nil {
			log.Error(err)
			os.Exit(3)
		}
		if len(queries) == 0 {
			log.Errorf("No slow queries found in the log files %v", opts.LogFiles)
			return
		}
	} else {
		queries = queriesFromProfiler(opts)
		if len(queries) == 0 {
			log.Errorf("No queries found in profiler information for database %q\n", opts.Database)
			return
		}
	}

	uptime := timeSpan(queries)

	queriesStats := queries.CalcQueriesStats(uptime)
	sortedQueryStats := sortQueries(queriesStats, opts.OrderBy)

	if opts.Limit > 0 && len(sortedQueryStats) > opts.Limit {
		sortedQueryStats = sortedQueryStats[:opts.Limit]
	}
	for i := range sortedQueryStats {
		sortedQueryStats[i].Rank = i + 1
	}

	rep := report{
		Headers:     getHeaders(opts),
		QueryTotals: queries.CalcTotalQueriesStats(uptime),
		QueryStats:  sortedQueryStats,
	}

	out, err := formatResults(rep, opts.OutputFormat, opts.ShowAll)
	if err != nil {
		log.Errorf("Cannot parse the report: %s", err.Error())
		os.Exit(5)
	}

	fmt.Println(string(out))
}

// queriesFromProfiler reads the queries from the system.profile collection
func queriesFromProfiler(opts *cliOptions) stats.Queries {
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

	filters := []filter.Filter{}

	if len(opts.SkipCollections) > 0 {
		filters = append(filters, filter.NewFilterByCollection(opts.SkipCollections))
	}

	cursor, err := client.Database(opts.Database).Collection("system.profile").Find(ctx, timeRangeFilter(opts))
	if err != nil {
		panic(err)
	}

	fp := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters())
	s := stats.New(fp)
	prof := profiler.NewProfiler(cursor, filters, nil, s)
	prof.Start(ctx)
	queries := <-prof.QueriesChan()

	return queries
}

// timeSpan returns the number of seconds between the first and the last query, used to
// calculate QPS. Like pt-query-digest, it is the time covered by the data being analyzed:
// the server uptime is much longer than the time covered by the (capped) system.profile
// collection or by the log files, and makes QPS values close to 0.
func timeSpan(queries stats.Queries) int64 {
	var first, last time.Time
	for _, q := range queries {
		if first.IsZero() || (!q.FirstSeen.IsZero() && q.FirstSeen.Before(first)) {
			first = q.FirstSeen
		}
		if q.LastSeen.After(last) {
			last = q.LastSeen
		}
	}
	span := int64(last.Sub(first).Seconds())
	if first.IsZero() || span < 1 {
		return 1
	}
	return span
}

// timeRangeFilter returns the system.profile filter for the --since and --until options
func timeRangeFilter(opts *cliOptions) primitive.M {
	ts := primitive.M{}
	if !opts.Since.IsZero() {
		ts["$gte"] = opts.Since
	}
	if !opts.Until.IsZero() {
		ts["$lte"] = opts.Until
	}
	if len(ts) == 0 {
		return primitive.M{}
	}
	return primitive.M{"ts": ts}
}

// queriesFromLogs reads the slow queries from MongoDB log files
func queriesFromLogs(opts *cliOptions) (stats.Queries, error) {
	filters := logFilters(opts)
	fp := fingerprinter.NewFingerprinter(fingerprinter.DefaultKeyFilters())
	s := stats.New(fp)
	currentFile := ""
	parser := logparser.New(logparser.Options{
		Since: opts.Since,
		Until: opts.Until,
		OnError: func(lineNumber int, err error) {
			log.Debugf("cannot parse slow query at %s:%d: %s", currentFile, lineNumber, err)
		},
	})

	statsErrors := 0

	add := func(doc proto.SystemProfile) error {
		for _, f := range filters {
			if !f(doc) {
				return nil
			}
		}
		if err := s.Add(doc); err != nil {
			statsErrors++
			log.Debugf("cannot process query %s %s at %s: %s", doc.Op, doc.Ns, doc.Ts, err)
			return nil
		}
		return nil
	}

	for _, file := range opts.LogFiles {
		currentFile = file
		if err := parseLogFile(parser, file, add); err != nil {
			return nil, err
		}
	}

	c := parser.Counters()
	log.Infof("Read %d lines, found %d slow query entries: %d parsed, %d out of the time range, "+
		"%d ignored (no query shape), %d could not be parsed", c.Lines, c.SlowQueries, c.Parsed,
		c.OutOfRange, c.Ignored, c.Unparsable+statsErrors)
	if skipped := c.Unparsable + statsErrors; skipped > 0 {
		log.Warnf("%d slow query entries could not be parsed and were skipped. "+
			"Use --log-level=debug for details", skipped)
	}

	return s.Queries(), nil
}

func parseLogFile(parser *logparser.Parser, file string, fn func(proto.SystemProfile) error) error {
	var r io.Reader
	if file == "-" {
		r = os.Stdin
	} else {
		f, err := os.Open(file)
		if err != nil {
			return fmt.Errorf("cannot open log file: %s", err)
		}
		defer f.Close()
		r = f
	}
	if err := parser.Parse(r, fn); err != nil {
		return fmt.Errorf("cannot read log file %s: %s", file, err)
	}
	return nil
}

// Databases skipped in log mode unless they are explicitly selected with --database
var internalDatabases = map[string]bool{"admin": true, "local": true, "config": true}

func logFilters(opts *cliOptions) []filter.Filter {
	filters := []filter.Filter{
		func(doc proto.SystemProfile) bool {
			db := strings.SplitN(doc.Ns, ".", 2)[0]
			if opts.Database != "" {
				return db == opts.Database
			}
			return !internalDatabases[db]
		},
	}
	if len(opts.SkipCollections) > 0 {
		filters = append(filters, filter.NewFilterByCollection(opts.SkipCollections))
	}
	return filters
}

func formatResults(rep report, outputFormat string, showAll []string) ([]byte, error) {
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
		if err := tt.Execute(buf, rep.QueryTotals); err != nil {
			return nil, fmt.Errorf("cannot format totals: %s", err)
		}

		show := map[string]bool{}
		for _, attr := range showAll {
			show[attr] = true
		}

		t, _ := template.New("query").Funcs(template.FuncMap{
			"Format":    format,
			"FormatQPS": formatQPS,
			"StringList": func(label, attr string, vals []stats.ValueCount, count int) string {
				if len(vals) == 0 {
					return ""
				}
				return fmt.Sprintf("# %-19s %s\n", label, formatStringList(vals, count, show[attr]))
			},
			"Sample": func(qs stats.QueryStats) string {
				if qs.SampleTs.IsZero() {
					return ""
				}
				return fmt.Sprintf("# %-19s %s (slowest: %.0f ms)\n", "Sample time", qs.SampleTs, qs.SampleQueryTime)
			},
		}).Parse(getQueryTemplate())

		for _, qs := range rep.QueryStats {
			if err := t.Execute(buf, qs); err != nil {
				return nil, fmt.Errorf("cannot format query %s: %s", qs.ID, err)
			}
		}
	}

	return buf.Bytes(), nil
}

// formatQPS formats QPS with 2 decimals. Values below 0.01 (common when analyzing slow
// queries) are shown with 2 significant digits instead, so they are not shown as 0.00.
func formatQPS(qps float64) string {
	if qps <= 0 || qps >= 0.01 {
		return fmt.Sprintf("% 0.2f", qps)
	}
	decimals := 1 - int(math.Floor(math.Log10(qps)))
	return strings.TrimRight(fmt.Sprintf("% 0.*f", decimals, qps), "0")
}

// Same limits used by pt-query-digest for string attributes (LINE_LENGTH and the
// --max-line-length default)
const maxLineLength = 74

// formatStringList formats the distinct values of a string attribute like pt-query-digest:
// a single value is printed alone; multiple values are printed with their count and
// percentage, most frequent first, as many as fit in a line followed by "... N more".
// Unlike pt-query-digest, values are never cut: a partial plan summary (e.g. an index key
// pattern) is useless.
func formatStringList(vals []stats.ValueCount, total int, showAll bool) string {
	if len(vals) == 1 {
		return vals[0].Value
	}

	parts := []string{}
	length := 0
	for _, v := range vals {
		pct := 0
		if total > 0 {
			pct = v.Count * 100 / total
		}
		s := fmt.Sprintf("%s (%d/%d%%)", v.Value, v.Count, pct)
		// Unlike pt-query-digest, always show at least the most frequent value
		if !showAll && len(parts) > 0 && length+len(s) > maxLineLength-27 {
			break
		}
		parts = append(parts, s)
		length += len(s) + 2
	}

	line := strings.Join(parts, ", ")
	if len(parts) < len(vals) {
		line += fmt.Sprintf("... %d more", len(vals)-len(parts))
	}
	return line
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
			"count,ratio,query-time,docs-scanned (or docs-examined),docs-returned. "+
			"- in front of the field name denotes reverse order. Default: "+DEFAULT_ORDERBY)
	gop.ListVarLong(&opts.SkipCollections, "skip-collections", 's', "A comma separated list of collections (namespaces) to skip."+
		"  Default: "+DEFAULT_SKIPCOLLECTIONS)

	gop.StringVarLong(&opts.AuthDB, "authenticationDatabase", 'a', "admin", "Database to use for optional MongoDB authentication. Default: admin")
	gop.StringVarLong(&opts.Database, "database", 'd', "", "MongoDB database to profile. With log files, only "+
		"analyze this database (default: all but admin, local and config)")
	gop.StringVarLong(&opts.LogLevel, "log-level", 'l', "Log level: error", "panic, fatal, error, warn, info, debug. Default: error")
	gop.StringVarLong(&opts.OutputFormat, "output-format", 'f', "text", "Output format: text, json. Default: text")
	gop.StringVarLong(&opts.Password, "password", 'p', "", "Password to use for optional MongoDB authentication").SetOptional()
	gop.StringVarLong(&opts.User, "username", 'u', "Username to use for optional MongoDB authentication")
	gop.StringVarLong(&opts.SSLCAFile, "sslCAFile", 0, "SSL CA cert file used for authentication")
	gop.StringVarLong(&opts.SSLPEMKeyFile, "sslPEMKeyFile", 0, "SSL client PEM file used for authentication")
	since := gop.StringLong("since", 0, "", "Only analyze queries newer than this value. Can be a date/time "+
		"(e.g. 2026-11-03T10:00:00Z, '2026-11-03 10:00:00', 2026-11-03) or a duration before now (e.g. 30m, 12h, 7d)")
	until := gop.StringLong("until", 0, "", "Only analyze queries older than this value. Same format as --since")
	gop.ListVarLong(&opts.ShowAll, "show-all", 0, "Comma separated list of attributes for which all values are shown "+
		"instead of only those fitting in one line: plan-summary,app-name,client,user")

	gop.SetParameters("[host[:port] | logfile [logfile ...]]")

	// Options are allowed after positional arguments, so keep parsing what is left
	// after each positional argument (getopt stops at the first one).
	positional := []string{}
	gop.Parse(os.Args)
	for gop.NArgs() > 0 {
		args := gop.Args()
		positional = append(positional, args[0])
		gop.Parse(args)
	}
	if opts.Help {
		gop.PrintUsage(os.Stdout)
		return nil, nil
	}

	logFiles, host, err := classifyArgs(positional)
	if err != nil {
		return nil, err
	}
	opts.LogFiles = logFiles
	if host != "" {
		opts.Host = host
	}

	now := time.Now()
	if *since != "" {
		if opts.Since, err = parseTimeOption(*since, now); err != nil {
			return nil, fmt.Errorf("invalid --since value: %s", err)
		}
	}
	if *until != "" {
		if opts.Until, err = parseTimeOption(*until, now); err != nil {
			return nil, fmt.Errorf("invalid --until value: %s", err)
		}
	}
	if !opts.Since.IsZero() && !opts.Until.IsZero() && opts.Until.Before(opts.Since) {
		return nil, fmt.Errorf("--until cannot be before --since")
	}

	validShowAll := map[string]bool{"plan-summary": true, "app-name": true, "client": true, "user": true}
	for _, attr := range opts.ShowAll {
		if !validShowAll[attr] {
			return nil, fmt.Errorf("invalid --show-all attribute %q", attr)
		}
	}

	if gop.IsSet("order-by") {
		validFields := []string{"count", "ratio", "query-time", "docs-scanned", "docs-examined", "docs-returned"}
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
		pass, err := term.ReadPassword(0)
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

// classifyArgs decides whether the positional arguments are log files or a host.
// They are log files if they exist (or are "-" for stdin) or look like log files.
// Only one host can be specified.
func classifyArgs(args []string) (logFiles []string, host string, err error) {
	if len(args) == 1 && !isLogFileArg(args[0]) {
		return nil, args[0], nil
	}
	for _, arg := range args {
		if !isLogFileArg(arg) {
			return nil, "", fmt.Errorf("log file %q does not exist. Only one host can be specified", arg)
		}
		logFiles = append(logFiles, arg)
	}
	return logFiles, "", nil
}

var reLogFileName = regexp.MustCompile(`\.log(\.[0-9T:\-]+)?$`)

func isLogFileArg(arg string) bool {
	if arg == "-" {
		return true
	}
	if fi, err := os.Stat(arg); err == nil && !fi.IsDir() {
		return true
	}
	// Report missing files instead of trying to connect to a host named like a file
	return reLogFileName.MatchString(arg)
}

var reRelativeTime = regexp.MustCompile(`^(\d+)([smhd])$`)

// parseTimeOption parses the --since and --until values. Values without time zone are
// interpreted in the local time zone.
func parseTimeOption(s string, now time.Time) (time.Time, error) {
	if m := reRelativeTime.FindStringSubmatch(s); m != nil {
		n, _ := strconv.Atoi(m[1])
		unit := map[string]time.Duration{"s": time.Second, "m": time.Minute, "h": time.Hour, "d": 24 * time.Hour}[m[2]]
		return now.Add(-time.Duration(n) * unit), nil
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return t, nil
	}
	for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02 15:04:05", "2006-01-02"} {
		if t, err := time.ParseInLocation(layout, s, time.Local); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("cannot parse %q", s)
}

func getHeaders(opts *cliOptions) []string {
	h := []string{
		fmt.Sprintf("%s - %s\n", toolname, time.Now().Format(time.RFC1123Z)),
	}
	if len(opts.LogFiles) > 0 {
		h = append(h, fmt.Sprintf("Log files: %s\n", strings.Join(opts.LogFiles, ", ")))
	} else {
		h = append(h, fmt.Sprintf("Host: %s\n", opts.Host))
	}
	h = append(h, fmt.Sprintf("Skipping profiled queries on these collections: %v\n", opts.SkipCollections))
	return h
}

func getQueryTemplate() string {
	t := `
# Query {{.Rank}}: {{FormatQPS .QPS}} QPS, ID {{.ID}}
# Ratio {{Format .Ratio 7.2}} (docs scanned/returned)
# Time range: {{.FirstSeen}} to {{.LastSeen}}
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count (docs)               {{printf "% 7d " .Count}}
# Exec Time ms        {{printf "% 4.0f" .QueryTime.Pct}}   {{printf "% 7.0f " .QueryTime.Total}}    {{printf "% 7.0f " .QueryTime.Min}}    {{printf "% 7.0f " .QueryTime.Max}}    {{printf "% 7.0f " .QueryTime.Avg}}    {{printf "% 7.0f " .QueryTime.Pct95}}    {{printf "% 7.0f " .QueryTime.StdDev}}    {{printf "% 7.0f " .QueryTime.Median}}
# Docs Scanned        {{printf "% 4.0f" .DocsExamined.Pct}}   {{Format .DocsExamined.Total 7.2}}    {{Format .DocsExamined.Min 7.2}}    {{Format .DocsExamined.Max 7.2}}    {{Format .DocsExamined.Avg 7.2}}    {{Format .DocsExamined.Pct95 7.2}}    {{Format .DocsExamined.StdDev 7.2}}    {{Format .DocsExamined.Median 7.2}}
# Docs Returned       {{printf "% 4.0f" .Returned.Pct}}   {{Format .Returned.Total 7.2}}    {{Format .Returned.Min 7.2}}    {{Format .Returned.Max 7.2}}    {{Format .Returned.Avg 7.2}}    {{Format .Returned.Pct95 7.2}}    {{Format .Returned.StdDev 7.2}}    {{Format .Returned.Median 7.2}}
# Bytes sent          {{printf "% 4.0f" .ResponseLength.Pct}}   {{Format .ResponseLength.Total 7.2}}    {{Format .ResponseLength.Min 7.2}}    {{Format .ResponseLength.Max 7.2}}    {{Format .ResponseLength.Avg 7.2}}    {{Format .ResponseLength.Pct95 7.2}}    {{Format .ResponseLength.StdDev 7.2}}    {{Format .ResponseLength.Median 7.2}}
# String:
# Namespace           {{.Namespace}}
# Operation           {{.Operation}}
# Fingerprint         {{.Fingerprint}}
{{StringList "Plan Summary" "plan-summary" .PlanSummaries .Count}}{{StringList "App Name" "app-name" .AppNames .Count}}{{StringList "Client" "client" .Clients .Count}}{{StringList "User" "user" .Users .Count}}{{Sample .}}# Query               {{.Query}}
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
# Docs Scanned        {{printf "% 4.0f" .DocsExamined.Pct}}   {{Format .DocsExamined.Total 7.2}}    {{Format .DocsExamined.Min 7.2}}    {{Format .DocsExamined.Max 7.2}}    {{Format .DocsExamined.Avg 7.2}}    {{Format .DocsExamined.Pct95 7.2}}    {{Format .DocsExamined.StdDev 7.2}}    {{Format .DocsExamined.Median 7.2}}
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
		case "docs-scanned", "docs-examined":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.DocsExamined.Max < c2.DocsExamined.Max
			}
		case "-docs-scanned", "-docs-examined":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.DocsExamined.Max > c2.DocsExamined.Max
			}

		//
		case "docs-returned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Returned.Max < c2.Returned.Max
			}
		case "-docs-returned":
			f = func(c1, c2 *stats.QueryStats) bool {
				return c1.Returned.Max > c2.Returned.Max
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
