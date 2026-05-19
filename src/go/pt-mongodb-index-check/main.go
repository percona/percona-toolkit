package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"strings"
	"text/template"
	"time"

	"github.com/alecthomas/kong"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"

	"github.com/percona/percona-toolkit/src/go/pt-mongodb-index-check/indexes"
	"github.com/percona/percona-toolkit/src/go/pt-mongodb-index-check/templates"
)

type cmdlineArgs struct {
	CheckUnused     struct{} `cmd:"" name:"check-unused" help:"Check for unused indexes."`
	CheckDuplicated struct{} `cmd:"" name:"check-duplicates" help:"Check for duplicated indexes."`
	CheckAll        struct{} `cmd:"" name:"check-all" help:"Check for unused and duplicated indexes."`
	ShowHelp        struct{} `cmd:"" default:"1"`
	Version         kong.VersionFlag

	AllDatabases bool     `name:"all-databases" xor:"db" help:"Check in all databases excluding system dbs"`
	Databases    []string `name:"databases" xor:"db" help:"Comma separated list of databases to check"`

	AllCollections bool     `name:"all-collections" xor:"colls" help:"Check in all collections in the selected databases."`
	Collections    []string `name:"collections" xor:"colls" help:"Comma separated list of collections to check"`
	URI            string   `name:"mongodb.uri" required:"" placeholder:"mongodb://host:port/admindb?options" help:"Connection URI"`
	JSON           bool     `name:"json" help:"Show output as JSON"`

	WarmupDays               float64 `name:"warmup-days" default:"7" help:"Minimum observation window (days) before flagging unused indexes"`
	LowUsageThreshold        float64 `name:"low-usage-threshold" default:"1.0" help:"Ops/day below which an index is considered low-usage"`
	LargeIndexSize           int64   `name:"large-index-size" default:"10485760" help:"Index size threshold in bytes for 'large' classification (default 10MB)"`
	IncludeLowUsage          bool    `name:"include-low-usage" default:"false" help:"Also report indexes with low but non-zero usage"`
	CrossReferenceDuplicates bool    `name:"cross-reference-duplicates" default:"true" help:"Combine unused + duplicate analysis for better recommendations"`
}

type response struct {
	Unused     []indexes.IndexStat     `json:"Unused,omitempty"`
	Duplicated []indexes.Duplicate     `json:"Duplicated,omitempty"`
	Analysis   []indexes.IndexAnalysis `json:"Analysis,omitempty"`
}

// analysisReportData is the template data for the sectioned analysis report.
type analysisReportData struct {
	ObsStart        string
	ObsEnd          string
	ObsDays         string
	TotalAnalyzed   int
	DatabaseCount   int
	CollectionCount int
	WriteRate       string

	SafeToDrop   []indexes.IndexAnalysis
	LikelyUnused []indexes.IndexAnalysis
	LowUsage     []indexes.IndexAnalysis
	Monitor      []indexes.IndexAnalysis
	Keep         []indexes.IndexAnalysis

	SafeToDropCount   int
	SafeToDropSavings int64
	LikelyUnusedCount int
	LowUsageCount     int
	MonitorCount      int
	KeepCount         int
}

// duplicateDisplayRow holds per-pair data for the rich duplicate text report.
type duplicateDisplayRow struct {
	Namespace     string
	Name          string
	Key           indexes.IndexKey
	ContainerName string
	ContainerKey  indexes.IndexKey
	Warning       string
	Reason        string
	Action        string
	PrefixSize    int64
	ContainerSize int64
	HasSizes      bool
}

// duplicateReportData is the template data for the sectioned duplicate report.
type duplicateReportData struct {
	TotalPairs      int
	DatabaseCount   int
	CollectionCount int
	Standard        []duplicateDisplayRow
	WithWarning     []duplicateDisplayRow
}

// buildDuplicateReportData transforms a raw []Duplicate into the display struct
// used by renderDuplicateReport. sizeByNS maps namespace → index name → size
// in bytes; pass nil to skip size display.
func buildDuplicateReportData(dups []indexes.Duplicate, sizeByNS map[string]map[string]int64) duplicateReportData {
	dbSet := make(map[string]struct{})
	nsSet := make(map[string]struct{})
	for _, d := range dups {
		nsSet[d.Namespace] = struct{}{}
		parts := strings.SplitN(d.Namespace, ".", 2)
		dbSet[parts[0]] = struct{}{}
	}

	data := duplicateReportData{
		TotalPairs:      len(dups),
		DatabaseCount:   len(dbSet),
		CollectionCount: len(nsSet),
	}

	collNameFn := func(ns string) string {
		parts := strings.SplitN(ns, ".", 2)
		if len(parts) == 2 {
			return parts[1]
		}
		return ns
	}

	for _, d := range dups {
		reason := fmt.Sprintf("'%s' is a key-order prefix of '%s'; any query served by '%s' can also use '%s'.",
			d.Name, d.ContainerName, d.Name, d.ContainerName)
		action := fmt.Sprintf("db.%s.dropIndex(%q)", collNameFn(d.Namespace), d.Name)

		row := duplicateDisplayRow{
			Namespace:     d.Namespace,
			Name:          d.Name,
			Key:           d.Key,
			ContainerName: d.ContainerName,
			ContainerKey:  d.ContainerKey,
			Warning:       d.Warning,
			Reason:        reason,
			Action:        action,
		}

		if sizes, ok := sizeByNS[d.Namespace]; ok {
			row.PrefixSize = sizes[d.Name]
			row.ContainerSize = sizes[d.ContainerName]
			row.HasSizes = true
		}

		if d.Warning == "" {
			data.Standard = append(data.Standard, row)
		} else {
			data.WithWarning = append(data.WithWarning, row)
		}
	}

	return data
}

// collectDuplicateSizes fetches collStats for each unique namespace in the
// duplicate list and returns a map of namespace → index name → size in bytes.
// Errors per namespace are logged as warnings and that namespace is omitted.
func collectDuplicateSizes(ctx context.Context, client *mongo.Client, dups []indexes.Duplicate) map[string]map[string]int64 {
	nsSet := make(map[string]struct{})
	for _, d := range dups {
		nsSet[d.Namespace] = struct{}{}
	}

	result := make(map[string]map[string]int64, len(nsSet))
	for ns := range nsSet {
		parts := strings.SplitN(ns, ".", 2)
		if len(parts) != 2 {
			continue
		}
		cs, err := indexes.CollectCollStats(ctx, client, parts[0], parts[1])
		if err != nil {
			log.Warnf("cannot get collStats for %s (sizes omitted from duplicate report): %s", ns, err)
			continue
		}
		result[ns] = cs.IndexSizes
	}
	return result
}

const (
	toolname = "pt-mongodb-index-check"
)

// We do not set anything here, these variables are defined by the Makefile
var (
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint
)

func main() {
	var args cmdlineArgs
	kongctx := kong.Parse(&args, kong.UsageOnError(),
		kong.Vars{"version": fmt.Sprintf("%s\nVersion %s\nBuild: %s using %s\nCommit: %s",
			toolname, Version, Build, GoVersion, Commit)})

	initLoggingForPTDEBUG()

	cmd := kongctx.Command()
	if cmd == "" {
		cmd = "(default)"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	if !strings.HasPrefix(args.URI, "mongodb") && !strings.HasPrefix(args.URI, "mongodb+srv") {
		args.URI = "mongodb://" + args.URI
	}

	log.Debugf("command=%s json=%v all-databases=%v all-collections=%v warmup-days=%.4f low-usage-threshold=%.4f large-index-size=%d include-low-usage=%v cross-reference-duplicates=%v",
		cmd, args.JSON, args.AllDatabases, args.AllCollections,
		args.WarmupDays, args.LowUsageThreshold, args.LargeIndexSize,
		args.IncludeLowUsage, args.CrossReferenceDuplicates)

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(args.URI))
	if err != nil {
		log.Fatalf("Cannot connect to the database: %q", err)
	}

	if err := client.Ping(ctx, readpref.Primary()); err != nil {
		log.Fatalf("Cannot connect to MongoDB at %s: %s", args.URI, err)
	}

	log.Debugf("connected (redacted-uri=%s)", redactMongoURI(args.URI))

	if args.AllDatabases {
		args.Databases, err = client.ListDatabaseNames(ctx, primitive.D{})
		if err != nil {
			log.Fatalf("cannot list all databases: %s", err)
		}
	}

	if !args.AllDatabases && len(args.Databases) == 0 {
		if dbName := extractDBFromURI(args.URI); dbName != "" {
			args.Databases = []string{dbName}
		} else {
			log.Fatal("Error: specify --databases or --all-databases to select which databases to check")
		}
	}

	if args.AllCollections {
		args.Collections = nil
	}

	log.Debugf("databases (%d): %v explicit-collections=%v",
		len(args.Databases), args.Databases, args.Collections)

	cfg := indexes.AnalysisConfig{
		WarmupDays:               args.WarmupDays,
		LowUsageThreshold:        args.LowUsageThreshold,
		LargeIndexSizeBytes:      args.LargeIndexSize,
		IncludeLowUsage:          args.IncludeLowUsage,
		CrossReferenceDuplicates: args.CrossReferenceDuplicates,
		Now:                      time.Now(),
	}

	resp := response{}
	var allAnalysis []indexes.IndexAnalysis
	var duplicates []indexes.Duplicate
	var dbCount, collCount int

	switch kongctx.Command() {
	case "check-unused":
		allAnalysis, dbCount, collCount = analyzeUnused(ctx, client, args.Databases, args.Collections, cfg, nil)
		resp.Analysis = allAnalysis
	case "check-duplicates":
		duplicates = findDuplicated(ctx, client, args.Databases, args.Collections)
		resp.Duplicated = duplicates
	case "check-all":
		duplicates = findDuplicated(ctx, client, args.Databases, args.Collections)
		resp.Duplicated = duplicates
		allAnalysis, dbCount, collCount = analyzeUnused(ctx, client, args.Databases, args.Collections, cfg, duplicates)
		resp.Analysis = allAnalysis
	default:
		kong.DefaultHelpPrinter(kong.HelpOptions{}, kongctx)
		return
	}

	showDupReport := kongctx.Command() == "check-duplicates" || kongctx.Command() == "check-all"
	var dupReport duplicateReportData
	if showDupReport {
		var sizeByNS map[string]map[string]int64
		if len(duplicates) > 0 {
			sizeByNS = collectDuplicateSizes(ctx, client, duplicates)
		}
		dupReport = buildDuplicateReportData(duplicates, sizeByNS)
	}

	fmt.Println(output(resp, args.JSON, allAnalysis, dbCount, collCount, dupReport, showDupReport))
}

// ptdebugEnabled mirrors Perl toolkit truthiness: $ENV{PTDEBUG} || 0 (so "0", unset, and "" are off).
func ptdebugEnabled() bool {
	v := os.Getenv("PTDEBUG")
	return v != "" && v != "0"
}

func initLoggingForPTDEBUG() {
	log.SetOutput(os.Stderr)
	if ptdebugEnabled() {
		log.SetLevel(log.DebugLevel)
		log.SetFormatter(&log.TextFormatter{FullTimestamp: true})
		return
	}
	log.SetLevel(log.WarnLevel)
}

// redactMongoURI returns a copy of uri with user password removed for safe logging.
func redactMongoURI(uri string) string {
	parsed, err := url.Parse(uri)
	if err != nil {
		return "<unparseable-uri>"
	}
	if parsed.User != nil {
		if _, hasPass := parsed.User.Password(); hasPass {
			username := parsed.User.Username()
			parsed.User = url.UserPassword(username, "xxx")
		}
	}
	return parsed.String()
}

func output(resp response, asJSON bool, analysis []indexes.IndexAnalysis, dbCount, collCount int, dupReport duplicateReportData, showDupReport bool) string {
	if asJSON {
		jsonStr, err := json.MarshalIndent(resp, "", "\t")
		if err != nil {
			log.Fatal("cannot encode the response as json")
		}
		return string(jsonStr)
	}

	buf := new(bytes.Buffer)

	if showDupReport {
		renderDuplicateReport(buf, dupReport)
	}

	if len(analysis) > 0 {
		renderAnalysisReport(buf, analysis, dbCount, collCount)
	} else {
		t := template.Must(template.New("unused").Parse(templates.Unused))
		if err := t.Execute(buf, resp.Unused); err != nil {
			log.Fatal(errors.Wrap(err, "cannot render unused indexes template"))
		}
	}

	return buf.String()
}

func renderDuplicateReport(buf *bytes.Buffer, data duplicateReportData) {
	funcMap := template.FuncMap{
		"formatBytes": indexes.FormatBytes,
		"collName": func(ns string) string {
			parts := strings.SplitN(ns, ".", 2)
			if len(parts) == 2 {
				return parts[1]
			}
			return ns
		},
	}
	t := template.Must(template.New("duplicated").Funcs(funcMap).Parse(templates.Duplicated))
	if err := t.Execute(buf, data); err != nil {
		log.Fatal(errors.Wrap(err, "cannot render duplicated indexes template"))
	}
}

func renderAnalysisReport(buf *bytes.Buffer, analysis []indexes.IndexAnalysis, dbCount, collCount int) {
	data := analysisReportData{
		ObsEnd:          time.Now().UTC().Format(time.RFC3339),
		TotalAnalyzed:   len(analysis),
		DatabaseCount:   dbCount,
		CollectionCount: collCount,
	}

	var oldestSince time.Time
	var writeRate float64

	for _, a := range analysis {
		if oldestSince.IsZero() || (!a.AccessSince.IsZero() && a.AccessSince.Before(oldestSince)) {
			oldestSince = a.AccessSince
		}
		if a.WriteOpsPerSec > writeRate {
			writeRate = a.WriteOpsPerSec
		}

		switch a.Recommendation {
		case indexes.RecommendSafeToDrop:
			data.SafeToDrop = append(data.SafeToDrop, a)
			data.SafeToDropSavings += a.IndexSizeBytes
		case indexes.RecommendLikelyUnused:
			data.LikelyUnused = append(data.LikelyUnused, a)
		case indexes.RecommendLowUsage:
			data.LowUsage = append(data.LowUsage, a)
		case indexes.RecommendMonitor:
			data.Monitor = append(data.Monitor, a)
		case indexes.RecommendKeepConstraint, indexes.RecommendKeepHidden, indexes.RecommendKeepPartial:
			data.Keep = append(data.Keep, a)
		}
	}

	if !oldestSince.IsZero() {
		data.ObsStart = oldestSince.UTC().Format(time.RFC3339)
		data.ObsDays = fmt.Sprintf("%.1f", time.Since(oldestSince).Hours()/24)
	} else {
		data.ObsStart = "unknown"
		data.ObsDays = "N/A"
	}
	data.WriteRate = fmt.Sprintf("%.0f", writeRate)
	data.SafeToDropCount = len(data.SafeToDrop)
	data.LikelyUnusedCount = len(data.LikelyUnused)
	data.LowUsageCount = len(data.LowUsage)
	data.MonitorCount = len(data.Monitor)
	data.KeepCount = len(data.Keep)

	funcMap := template.FuncMap{
		"formatBytes": indexes.FormatBytes,
		"collName": func(ns string) string {
			parts := strings.SplitN(ns, ".", 2)
			if len(parts) == 2 {
				return parts[1]
			}
			return ns
		},
		"tagFor": func(a indexes.IndexAnalysis) string {
			switch {
			case a.IsUnique:
				return "  [UNIQUE]"
			case a.IsTTL:
				return "  [TTL]"
			case a.IsHidden:
				return "  [HIDDEN]"
			default:
				return ""
			}
		},
	}

	t := template.Must(template.New("analysis").Funcs(funcMap).Parse(templates.Analysis))
	if err := t.Execute(buf, data); err != nil {
		log.Fatal(errors.Wrap(err, "cannot render analysis template"))
	}
}

func analyzeUnused(
	ctx context.Context,
	client *mongo.Client,
	databases, collections []string,
	cfg indexes.AnalysisConfig,
	duplicates []indexes.Duplicate,
) ([]indexes.IndexAnalysis, int, int) {
	var allAnalysis []indexes.IndexAnalysis
	var dbCount, collCount int

	wr, err := indexes.CollectServerWriteRate(ctx, client)
	if err != nil {
		log.Warnf("cannot get server write rate (will use 0): %s", err)
	} else if log.IsLevelEnabled(log.DebugLevel) {
		log.Debugf("server write-rate: %.6f ops/s uptime-sec=%d", wr.WriteOpsPerSec, wr.Uptime)
	}

	colls := make([]string, len(collections))
	copy(colls, collections)

	for _, database := range databases {
		if indexes.IsSystemDB(database) {
			continue
		}
		dbCount++

		if len(collections) == 0 {
			colls, err = client.Database(database).ListCollectionNames(ctx, primitive.D{})
			if err != nil {
				log.Errorf("cannot get the list of collections for the database %s: %s", database, err)
				continue
			}
		}

		for _, collection := range colls {
			if indexes.IsSystemCollection(collection) {
				continue
			}

			collCount++
			ns := database + "." + collection

			log.Debugf("analyze-unused start namespace=%s", ns)

			stats, err := indexes.CollectIndexStats(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error collecting $indexStats for %s: %s", ns, err)
				continue
			}
			stats = indexes.AggregateShardStats(stats)

			metadata, err := indexes.CollectIndexMetadata(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error collecting index metadata for %s: %s", ns, err)
				continue
			}

			cs, err := indexes.CollectCollStats(ctx, client, database, collection)
			if err != nil {
				log.Warnf("cannot get collStats for %s (sizes will be 0): %s", ns, err)
			}

			records := indexes.DeduplicateIndexRecords(indexes.BuildIndexRecords(stats, metadata, cs, wr, ns))

			log.Debugf("analyze-unused done namespace=%s indexStats=%d metadata=%d records=%d",
				ns, len(stats), len(metadata), len(records))

			if cfg.CrossReferenceDuplicates && duplicates != nil {
				indexes.CrossReferenceDuplicates(records, duplicates, stats)
			}

			for _, rec := range records {
				a := indexes.ScoreIndex(rec, cfg)
				if a.Recommendation == "" {
					continue
				}
				if a.Recommendation == indexes.RecommendLowUsage && !cfg.IncludeLowUsage {
					continue
				}
				allAnalysis = append(allAnalysis, a)
			}
		}
	}

	return allAnalysis, dbCount, collCount
}

func findDuplicated(ctx context.Context, client *mongo.Client, databases []string, collections []string) []indexes.Duplicate {
	duplicated := []indexes.Duplicate{}
	var err error

	colls := make([]string, len(collections))
	copy(colls, collections)

	for _, database := range databases {
		if indexes.IsSystemDB(database) {
			continue
		}

		if len(collections) == 0 {
			colls, err = client.Database(database).ListCollectionNames(ctx, primitive.D{})
			if err != nil {
				log.Errorf("cannot get the list of collections for the database %s", database)
				continue
			}
		}

		for _, collection := range colls {
			if indexes.IsSystemCollection(collection) {
				continue
			}

			log.Debugf("check-duplicates start namespace=%s.%s", database, collection)

			dups, err := indexes.FindDuplicated(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error while checking duplicated indexes in %s.%s: %s", database, collection, err)
				continue
			}

			log.Debugf("check-duplicates done namespace=%s.%s duplicate-groups=%d", database, collection, len(dups))

			duplicated = append(duplicated, dups...)
		}
	}

	return duplicated
}

// extractDBFromURI parses the MongoDB connection URI and returns the database
// name if one is present in the path component (e.g., mongodb://host:port/mydb).
// Returns empty string if no database is specified or the URI is the "admin" default.
func extractDBFromURI(uri string) string {
	parsed, err := url.Parse(uri)
	if err != nil {
		return ""
	}
	if parsed.Scheme != "mongodb" && parsed.Scheme != "mongodb+srv" {
		return ""
	}
	db := strings.TrimPrefix(parsed.Path, "/")
	if db == "" || db == "admin" {
		return ""
	}
	return db
}
