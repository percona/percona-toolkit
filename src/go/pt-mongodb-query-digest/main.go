package main

import (
	"crypto/md5"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"text/template"
	"time"

	"github.com/howeyc/gopass"
	"github.com/kr/pretty"
	"github.com/montanaflynn/stats"
	"github.com/pborman/getopt"
	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/percona/pmgo"
	log "github.com/sirupsen/logrus"
	"gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
)

const (
	TOOLNAME        = "pt-mongodb-query-digest"
	MAX_DEPTH_LEVEL = 10

	DEFAULT_AUTHDB          = "admin"
	DEFAULT_HOST            = "localhost:27017"
	DEFAULT_LOGLEVEL        = "warn"
	DEFAULT_ORDERBY         = "-count"         // comma separated list
	DEFAULT_SKIPCOLLECTIONS = "system.profile" // comma separated list
)

var (
	Build     string = "01-01-1980"
	GoVersion string = "1.8"
	Version   string = "3.0.1"

	CANNOT_GET_QUERY_ERROR = errors.New("cannot get query field from the profile document (it is not a map)")

	// This is a regexp array to filter out the keys we don't want in the fingerprint
	keyFilters = func() []string {
		return []string{"^shardVersion$", "^\\$"}
	}
)

type iter interface {
	All(result interface{}) error
	Close() error
	Err() error
	For(result interface{}, f func() error) (err error)
	Next(result interface{}) bool
	Timeout() bool
}

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

// This func receives a doc from the profiler and returns:
// true : the document must be considered
// false: the document must be skipped
type docsFilter func(proto.SystemProfile) bool

type statsArray []stat

func (a statsArray) Len() int           { return len(a) }
func (a statsArray) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a statsArray) Less(i, j int) bool { return a[i].Count < a[j].Count }

type times []time.Time

func (a times) Len() int           { return len(a) }
func (a times) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a times) Less(i, j int) bool { return a[i].Before(a[j]) }

type stat struct {
	ID             string
	Operation      string
	Fingerprint    string
	Namespace      string
	Query          map[string]interface{}
	Count          int
	TableScan      bool
	NScanned       []float64
	NReturned      []float64
	QueryTime      []float64 // in milliseconds
	ResponseLength []float64
	LockTime       times
	BlockedTime    times
	FirstSeen      time.Time
	LastSeen       time.Time
}

type groupKey struct {
	Operation   string
	Fingerprint string
	Namespace   string
}

type statistics struct {
	Pct    float64
	Total  float64
	Min    float64
	Max    float64
	Avg    float64
	Pct95  float64
	StdDev float64
	Median float64
}

type queryInfo struct {
	Count          int
	Operation      string
	Query          string
	Fingerprint    string
	FirstSeen      time.Time
	ID             string
	LastSeen       time.Time
	Namespace      string
	NoVersionCheck bool
	QPS            float64
	QueryTime      statistics
	Rank           int
	Ratio          float64
	ResponseLength statistics
	Returned       statistics
	Scanned        statistics
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
		fmt.Errorf("cannot set log level: %s", err.Error())
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

	if isProfilerEnabled == false {
		count, err := systemProfileDocsCount(session, di.Database)
		if err != nil || count == 0 {
			log.Error("Profiler is not enabled")
			os.Exit(5)
		}
		fmt.Printf("Profiler is disabled for the %q database but there are %d documents in the system.profile collection.\n",
			di.Database, count)
		fmt.Println("Using those documents for the stats")
	}

	filters := []docsFilter{}

	if len(opts.SkipCollections) > 0 {
		// Sanitize the param. using --skip-collections="" will produce an 1 element array but
		// that element will be empty. The same would be using --skip-collections=a,,d
		cols := []string{}
		for _, c := range opts.SkipCollections {
			if strings.TrimSpace(c) != "" {
				cols = append(cols, c)
			}
		}
		if len(cols) > 0 {
			// This func receives a doc from the profiler and returns:
			// true : the document must be considered
			// false: the document must be skipped
			filterSystemProfile := func(doc proto.SystemProfile) bool {
				for _, collection := range cols {
					if strings.HasSuffix(doc.Ns, collection) {
						return false
					}
				}
				return true
			}
			filters = append(filters, filterSystemProfile)
		}
	}

	query := bson.M{"op": bson.M{"$nin": []string{"getmore", "delete"}}}
	i := session.DB(di.Database).C("system.profile").Find(query).Sort("-$natural").Iter()
	queries := sortQueries(getData(i, filters), opts.OrderBy)

	uptime := uptime(session)

	printHeader(opts)

	queryTotals := calcTotalQueryStats(queries, uptime)
	tt, _ := template.New("query").Funcs(template.FuncMap{
		"Format": format,
	}).Parse(getTotalsTemplate())
	tt.Execute(os.Stdout, queryTotals)

	queryStats := calcQueryStats(queries, uptime)
	t, _ := template.New("query").Funcs(template.FuncMap{
		"Format": format,
	}).Parse(getQueryTemplate())

	if opts.Limit > 0 && len(queryStats) > opts.Limit {
		queryStats = queryStats[:opts.Limit]
	}
	for _, qs := range queryStats {
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

func calcTotalQueryStats(queries []stat, uptime int64) queryInfo {
	qi := queryInfo{}
	qs := stat{}
	_, totalScanned, totalReturned, totalQueryTime, totalBytes := calcTotals(queries)
	for _, query := range queries {
		qs.NScanned = append(qs.NScanned, query.NScanned...)
		qs.NReturned = append(qs.NReturned, query.NReturned...)
		qs.QueryTime = append(qs.QueryTime, query.QueryTime...)
		qs.ResponseLength = append(qs.ResponseLength, query.ResponseLength...)
		qi.Count += query.Count
	}

	qi.Scanned = calcStats(qs.NScanned)
	qi.Returned = calcStats(qs.NReturned)
	qi.QueryTime = calcStats(qs.QueryTime)
	qi.ResponseLength = calcStats(qs.ResponseLength)

	if totalScanned > 0 {
		qi.Scanned.Pct = qi.Scanned.Total * 100 / totalScanned
	}
	if totalReturned > 0 {
		qi.Returned.Pct = qi.Returned.Total * 100 / totalReturned
	}
	if totalQueryTime > 0 {
		qi.QueryTime.Pct = qi.QueryTime.Total * 100 / totalQueryTime
	}
	if totalBytes > 0 {
		qi.ResponseLength.Pct = qi.ResponseLength.Total / totalBytes
	}
	if qi.Returned.Total > 0 {
		qi.Ratio = qi.Scanned.Total / qi.Returned.Total
	}

	return qi
}

func calcQueryStats(queries []stat, uptime int64) []queryInfo {
	queryStats := []queryInfo{}
	_, totalScanned, totalReturned, totalQueryTime, totalBytes := calcTotals(queries)
	for rank, query := range queries {
		buf, _ := json.Marshal(query.Query)
		qi := queryInfo{
			Rank:           rank,
			Count:          query.Count,
			ID:             query.ID,
			Operation:      query.Operation,
			Query:          string(buf),
			Fingerprint:    query.Fingerprint,
			Scanned:        calcStats(query.NScanned),
			Returned:       calcStats(query.NReturned),
			QueryTime:      calcStats(query.QueryTime),
			ResponseLength: calcStats(query.ResponseLength),
			FirstSeen:      query.FirstSeen,
			LastSeen:       query.LastSeen,
			Namespace:      query.Namespace,
			QPS:            float64(query.Count) / float64(uptime),
		}
		if totalScanned > 0 {
			qi.Scanned.Pct = qi.Scanned.Total * 100 / totalScanned
		}
		if totalReturned > 0 {
			qi.Returned.Pct = qi.Returned.Total * 100 / totalReturned
		}
		if totalQueryTime > 0 {
			qi.QueryTime.Pct = qi.QueryTime.Total * 100 / totalQueryTime
		}
		if totalBytes > 0 {
			qi.ResponseLength.Pct = qi.ResponseLength.Total / totalBytes
		}
		if qi.Returned.Total > 0 {
			qi.Ratio = qi.Scanned.Total / qi.Returned.Total
		}
		queryStats = append(queryStats, qi)
	}
	return queryStats
}

func getTotals(queries []stat) stat {

	qt := stat{}
	for _, query := range queries {
		qt.NScanned = append(qt.NScanned, query.NScanned...)
		qt.NReturned = append(qt.NReturned, query.NReturned...)
		qt.QueryTime = append(qt.QueryTime, query.QueryTime...)
		qt.ResponseLength = append(qt.ResponseLength, query.ResponseLength...)
	}
	return qt

}

func calcTotals(queries []stat) (totalCount int, totalScanned, totalReturned, totalQueryTime, totalBytes float64) {

	for _, query := range queries {
		totalCount += query.Count

		scanned, _ := stats.Sum(query.NScanned)
		totalScanned += scanned

		returned, _ := stats.Sum(query.NReturned)
		totalReturned += returned

		queryTime, _ := stats.Sum(query.QueryTime)
		totalQueryTime += queryTime

		bytes, _ := stats.Sum(query.ResponseLength)
		totalBytes += bytes
	}
	return
}

func calcStats(samples []float64) statistics {
	var s statistics
	s.Total, _ = stats.Sum(samples)
	s.Min, _ = stats.Min(samples)
	s.Max, _ = stats.Max(samples)
	s.Avg, _ = stats.Mean(samples)
	s.Pct95, _ = stats.PercentileNearestRank(samples, 95)
	s.StdDev, _ = stats.StandardDeviation(samples)
	s.Median, _ = stats.Median(samples)
	return s
}

func getData(i iter, filters []docsFilter) []stat {
	var doc proto.SystemProfile
	stats := make(map[groupKey]*stat)

	log.Debug(`Documents returned by db.getSiblinfDB("<dbnamehere>").system.profile.Find({"op": {"$nin": []string{"getmore", "delete"}}).Sort("-$natural")`)

	for i.Next(&doc) && i.Err() == nil {
		valid := true
		for _, filter := range filters {
			if filter(doc) == false {
				valid = false
				break
			}
		}
		if !valid {
			continue
		}

		log.Debugln("====================================================================================================")
		log.Debug(pretty.Sprint(doc))
		if len(doc.Query) > 0 {

			fp, err := fingerprint(doc.Query)
			if err != nil {
				log.Errorf("cannot get fingerprint: %s", err.Error())
				continue
			}
			var s *stat
			var ok bool
			key := groupKey{
				Operation:   doc.Op,
				Fingerprint: fp,
				Namespace:   doc.Ns,
			}
			if s, ok = stats[key]; !ok {
				realQuery, _ := getQueryField(doc.Query)
				s = &stat{
					ID:          fmt.Sprintf("%x", md5.Sum([]byte(fp+doc.Ns))),
					Operation:   doc.Op,
					Fingerprint: fp,
					Namespace:   doc.Ns,
					TableScan:   false,
					Query:       realQuery,
				}
				stats[key] = s
			}
			s.Count++
			s.NScanned = append(s.NScanned, float64(doc.DocsExamined))
			s.NReturned = append(s.NReturned, float64(doc.Nreturned))
			s.QueryTime = append(s.QueryTime, float64(doc.Millis))
			s.ResponseLength = append(s.ResponseLength, float64(doc.ResponseLength))
			var zeroTime time.Time
			if s.FirstSeen == zeroTime || s.FirstSeen.After(doc.Ts) {
				s.FirstSeen = doc.Ts
			}
			if s.LastSeen == zeroTime || s.LastSeen.Before(doc.Ts) {
				s.LastSeen = doc.Ts
			}
		}
	}

	// We need to sort the data but a hash cannot be sorted so, convert the hash having
	// the results to a slice
	sa := statsArray{}
	for _, s := range stats {
		sa = append(sa, *s)
	}

	sort.Sort(sa)
	return sa
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

func getQueryField(query map[string]interface{}) (map[string]interface{}, error) {
	// MongoDB 3.0
	if squery, ok := query["$query"]; ok {
		// just an extra check to ensure this type assertion won't fail
		if ssquery, ok := squery.(map[string]interface{}); ok {
			return ssquery, nil
		}
		return nil, CANNOT_GET_QUERY_ERROR
	}
	// MongoDB 3.2+
	if squery, ok := query["filter"]; ok {
		if ssquery, ok := squery.(map[string]interface{}); ok {
			return ssquery, nil
		}
		return nil, CANNOT_GET_QUERY_ERROR
	}
	return query, nil
}

// Query is the top level map query element
// Example for MongoDB 3.2+
//     "query" : {
//        "find" : "col1",
//        "filter" : {
//            "s2" : {
//                "$lt" : "54701",
//                "$gte" : "73754"
//            }
//        },
//        "sort" : {
//            "user_id" : 1
//        }
//     }
func fingerprint(query map[string]interface{}) (string, error) {

	realQuery, err := getQueryField(query)
	if err != nil {
		// Try to encode doc.Query as json for prettiness
		if buf, err := json.Marshal(realQuery); err == nil {
			return "", fmt.Errorf("%v for query %s", err, string(buf))
		}
		// If we cannot encode as json, return just the error message without the query
		return "", err
	}
	retKeys := keys(realQuery, 0)

	sort.Strings(retKeys)

	// if there is a sort clause in the query, we have to add all fields in the sort
	// fields list that are not in the query keys list (retKeys)
	if sortKeys, ok := query["sort"]; ok {
		if sortKeysMap, ok := sortKeys.(map[string]interface{}); ok {
			sortKeys := mapKeys(sortKeysMap, 0)
			for _, sortKey := range sortKeys {
				if !inSlice(sortKey, retKeys) {
					retKeys = append(retKeys, sortKey)
				}
			}
		}
	}

	return strings.Join(retKeys, ","), nil
}

func inSlice(str string, list []string) bool {
	for _, v := range list {
		if v == str {
			return true
		}
	}
	return false
}

func keys(query map[string]interface{}, level int) []string {
	ks := []string{}
	for key, value := range query {
		if shouldSkipKey(key) {
			continue
		}
		ks = append(ks, key)
		if m, ok := value.(map[string]interface{}); ok {
			level++
			if level <= MAX_DEPTH_LEVEL {
				ks = append(ks, keys(m, level)...)
			}
		}
	}
	sort.Strings(ks)
	return ks
}

func mapKeys(query map[string]interface{}, level int) []string {
	ks := []string{}
	for key, value := range query {
		ks = append(ks, key)
		if m, ok := value.(map[string]interface{}); ok {
			level++
			if level <= MAX_DEPTH_LEVEL {
				ks = append(ks, keys(m, level)...)
			}
		}
	}
	sort.Strings(ks)
	return ks
}

func shouldSkipKey(key string) bool {
	for _, filter := range keyFilters() {
		if matched, _ := regexp.MatchString(filter, key); matched {
			return true
		}
	}
	return false
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

type lessFunc func(p1, p2 *stat) bool

type multiSorter struct {
	queries []stat
	less    []lessFunc
}

// Sort sorts the argument slice according to the less functions passed to OrderedBy.
func (ms *multiSorter) Sort(queries []stat) {
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

func sortQueries(queries []stat, orderby []string) []stat {
	sortFuncs := []lessFunc{}
	for _, field := range orderby {
		var f lessFunc
		switch field {
		//
		case "count":
			f = func(c1, c2 *stat) bool {
				return c1.Count < c2.Count
			}
		case "-count":
			f = func(c1, c2 *stat) bool {
				return c1.Count > c2.Count
			}

		case "ratio":
			f = func(c1, c2 *stat) bool {
				ns1, _ := stats.Max(c1.NScanned)
				ns2, _ := stats.Max(c2.NScanned)
				nr1, _ := stats.Max(c1.NReturned)
				nr2, _ := stats.Max(c2.NReturned)
				ratio1 := ns1 / nr1
				ratio2 := ns2 / nr2
				return ratio1 < ratio2
			}
		case "-ratio":
			f = func(c1, c2 *stat) bool {
				ns1, _ := stats.Max(c1.NScanned)
				ns2, _ := stats.Max(c2.NScanned)
				nr1, _ := stats.Max(c1.NReturned)
				nr2, _ := stats.Max(c2.NReturned)
				ratio1 := ns1 / nr1
				ratio2 := ns2 / nr2
				return ratio1 > ratio2
			}

		//
		case "query-time":
			f = func(c1, c2 *stat) bool {
				qt1, _ := stats.Max(c1.QueryTime)
				qt2, _ := stats.Max(c2.QueryTime)
				return qt1 < qt2
			}
		case "-query-time":
			f = func(c1, c2 *stat) bool {
				qt1, _ := stats.Max(c1.QueryTime)
				qt2, _ := stats.Max(c2.QueryTime)
				return qt1 > qt2
			}

		//
		case "docs-scanned":
			f = func(c1, c2 *stat) bool {
				ns1, _ := stats.Max(c1.NScanned)
				ns2, _ := stats.Max(c2.NScanned)
				return ns1 < ns2
			}
		case "-docs-scanned":
			f = func(c1, c2 *stat) bool {
				ns1, _ := stats.Max(c1.NScanned)
				ns2, _ := stats.Max(c2.NScanned)
				return ns1 > ns2
			}

		//
		case "docs-returned":
			f = func(c1, c2 *stat) bool {
				nr1, _ := stats.Max(c1.NReturned)
				nr2, _ := stats.Max(c2.NReturned)
				return nr1 < nr2
			}
		case "-docs-returned":
			f = func(c1, c2 *stat) bool {
				nr1, _ := stats.Max(c1.NReturned)
				nr2, _ := stats.Max(c2.NReturned)
				return nr1 > nr2
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

		if member.StateStr == "configsvr" {
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
