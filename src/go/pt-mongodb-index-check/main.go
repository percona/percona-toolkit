// This program is copyright 2022-2026 Percona LLC and/or its affiliates.
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

	Timeout time.Duration `name:"timeout" default:"60s" help:"Time limit for the whole run, e.g. 90s or 5m"`

	WarmupDays               float64 `name:"warmup-days" default:"7" help:"Minimum observation window (days) before flagging unused indexes"`
	LowUsageThreshold        float64 `name:"low-usage-threshold" default:"1.0" help:"Ops/day below which an index is considered low-usage"`
	LargeIndexSize           int64   `name:"large-index-size" default:"10485760" help:"Index size threshold in bytes for 'large' classification (default 10MB)"`
	IncludeLowUsage          bool    `name:"include-low-usage" default:"false" help:"Also report indexes with low but non-zero usage"`
	CrossReferenceDuplicates bool    `name:"cross-reference-duplicates" default:"true" help:"Combine unused + duplicate analysis for better recommendations"`
}

type response struct {
	Duplicated        []indexes.Duplicate        `json:"Duplicated,omitempty"`
	SkippedDuplicates []indexes.SkippedDuplicate `json:"SkippedDuplicates,omitempty"`
	Analysis          []indexes.IndexAnalysis    `json:"Analysis,omitempty"`
}

// analysisReportData is the template data for the sectioned analysis report.
type analysisReportData struct {
	ObsStart        string
	ObsEnd          string
	ObsDays         string
	TotalAnalyzed   int
	DatabaseCount   int
	CollectionCount int
	NoCandidates    bool

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

type analysisScope struct {
	Databases   int
	Collections int
	Indexes     int
	OldestSince time.Time
}

// duplicateDisplayRow holds per-pair data for the rich duplicate text report.
type duplicateDisplayRow struct {
	Namespace     string
	Name          string
	Key           indexes.IndexKey
	ContainerName string
	ContainerKey  indexes.IndexKey
	Warning       string
	Tag           string
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
	Skipped         []indexes.SkippedDuplicate
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

	for _, d := range dups {
		reason := fmt.Sprintf("'%s' is a key-order prefix of '%s'; any query served by '%s' can also use '%s'.",
			d.Name, d.ContainerName, d.Name, d.ContainerName)
		row := duplicateDisplayRow{
			Namespace:     d.Namespace,
			Name:          d.Name,
			Key:           d.Key,
			ContainerName: d.ContainerName,
			ContainerKey:  d.ContainerKey,
			Warning:       d.Warning,
			Reason:        reason,
		}

		if d.Warning == "" {
			row.Action = dropIndexAction(d.Namespace, d.Name)
		}

		if d.Constraint != "" {
			row.Tag = "[" + strings.ToUpper(d.Constraint) + "]"
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

func dropIndexAction(namespace, index string) string {
	database, collection, _ := strings.Cut(namespace, ".")
	return fmt.Sprintf("db.getSiblingDB(%q).getCollection(%q).dropIndex(%q)", database, collection, index)
}

// collectDuplicateSizes returns namespace → index name → size in bytes. Sizes in
// known are reused for any namespace; collStats runs only for the other namespaces
// that have a redundant pair. Errors are logged and the namespace omitted.
func collectDuplicateSizes(
	ctx context.Context,
	client *mongo.Client,
	dups []indexes.Duplicate,
	known map[string]map[string]int64,
) map[string]map[string]int64 {
	result := make(map[string]map[string]int64)
	tried := make(map[string]bool)

	for _, d := range dups {
		if tried[d.Namespace] {
			continue
		}

		if sizes, ok := known[d.Namespace]; ok {
			tried[d.Namespace] = true
			result[d.Namespace] = sizes
			continue
		}

		if d.Warning != "" {
			continue
		}
		tried[d.Namespace] = true

		database, collection, _ := strings.Cut(d.Namespace, ".")
		cs, err := indexes.CollectCollStats(ctx, client, database, collection)
		if err != nil {
			log.Warnf("cannot get collStats for %s (sizes omitted from duplicate report): %s", d.Namespace, err)
			continue
		}
		result[d.Namespace] = cs.IndexSizes
	}

	return result
}

func needsSizes(analysis []indexes.IndexAnalysis) bool {
	for _, a := range analysis {
		switch a.Recommendation {
		case indexes.RecommendSafeToDrop, indexes.RecommendLikelyUnused, indexes.RecommendLowUsage:
			return true
		}
	}

	return false
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
	switch cmd {
	case "check-unused", "check-duplicates", "check-all":
	default:
		kongctx.PrintUsage(false)
		return
	}

	if args.Timeout <= 0 {
		log.Fatalf("--timeout must be greater than 0, got %s", args.Timeout)
	}

	ctx, cancel := context.WithTimeout(context.Background(), args.Timeout)
	defer cancel()

	if !strings.HasPrefix(args.URI, "mongodb") && !strings.HasPrefix(args.URI, "mongodb+srv") {
		args.URI = "mongodb://" + args.URI
	}

	log.Debugf("command=%s json=%v timeout=%s all-databases=%v all-collections=%v warmup-days=%.4f low-usage-threshold=%.4f large-index-size=%d include-low-usage=%v cross-reference-duplicates=%v",
		cmd, args.JSON, args.Timeout, args.AllDatabases, args.AllCollections,
		args.WarmupDays, args.LowUsageThreshold, args.LargeIndexSize,
		args.IncludeLowUsage, args.CrossReferenceDuplicates)

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(args.URI))
	if err != nil {
		log.Fatalf("Cannot connect to the database: %q", err)
	}

	if err := client.Ping(ctx, readpref.Primary()); err != nil {
		log.Fatalf("Cannot connect to MongoDB at %s: %s", redactMongoURI(args.URI), err)
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
	var skipped []indexes.SkippedDuplicate
	var scope analysisScope
	var sizeByNS map[string]map[string]int64

	switch cmd {
	case "check-unused":
		allAnalysis, scope, _ = analyzeUnused(ctx, client, args.Databases, args.Collections, cfg, nil)
		resp.Analysis = allAnalysis
	case "check-duplicates":
		duplicates, skipped = findDuplicated(ctx, client, args.Databases, args.Collections)
		resp.Duplicated, resp.SkippedDuplicates = duplicates, skipped
	case "check-all":
		duplicates, skipped = findDuplicated(ctx, client, args.Databases, args.Collections)
		resp.Duplicated, resp.SkippedDuplicates = duplicates, skipped
		allAnalysis, scope, sizeByNS = analyzeUnused(ctx, client, args.Databases, args.Collections, cfg, duplicates)
		resp.Analysis = allAnalysis
	}

	showDupReport := cmd == "check-duplicates" || cmd == "check-all"
	var dupReport duplicateReportData
	if showDupReport && !args.JSON {
		dupReport = buildDuplicateReportData(duplicates, collectDuplicateSizes(ctx, client, duplicates, sizeByNS))
		dupReport.Skipped = skipped
	}

	if ctx.Err() != nil {
		log.Fatalf("The --timeout=%s limit was reached before all collections were checked; run again with a larger --timeout", args.Timeout)
	}

	showAnalysis := cmd == "check-unused" || cmd == "check-all"

	fmt.Println(output(resp, args.JSON, allAnalysis, scope, dupReport, showDupReport, showAnalysis))
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
		return "<unparsable-uri>"
	}
	if parsed.User != nil {
		if _, hasPass := parsed.User.Password(); hasPass {
			username := parsed.User.Username()
			parsed.User = url.UserPassword(username, "xxx")
		}
	}
	return parsed.String()
}

func output(resp response, asJSON bool, analysis []indexes.IndexAnalysis, scope analysisScope, dupReport duplicateReportData,
	showDupReport, showAnalysis bool,
) string {
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

	if showAnalysis {
		renderAnalysisReport(buf, analysis, scope)
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

func renderAnalysisReport(buf *bytes.Buffer, analysis []indexes.IndexAnalysis, scope analysisScope) {
	data := analysisReportData{
		ObsEnd:          time.Now().UTC().Format(time.RFC3339),
		TotalAnalyzed:   scope.Indexes,
		DatabaseCount:   scope.Databases,
		CollectionCount: scope.Collections,
		NoCandidates:    scope.Indexes > 0 && len(analysis) == 0,
	}

	for _, a := range analysis {
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

	if !scope.OldestSince.IsZero() {
		data.ObsStart = scope.OldestSince.UTC().Format(time.RFC3339)
		data.ObsDays = fmt.Sprintf("%.1f", time.Since(scope.OldestSince).Hours()/24)
	} else {
		data.ObsStart = "unknown"
		data.ObsDays = "N/A"
	}
	data.SafeToDropCount = len(data.SafeToDrop)
	data.LikelyUnusedCount = len(data.LikelyUnused)
	data.LowUsageCount = len(data.LowUsage)
	data.MonitorCount = len(data.Monitor)
	data.KeepCount = len(data.Keep)

	funcMap := template.FuncMap{
		"formatBytes": indexes.FormatBytes,
		"dropAction":  dropIndexAction,
		"tagFor": func(a indexes.IndexAnalysis) string {
			switch {
			case a.IsUnique:
				return "  [UNIQUE]"
			case a.IsTTL:
				return "  [TTL]"
			case a.IsShardKey:
				return "  [SHARD KEY]"
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
) ([]indexes.IndexAnalysis, analysisScope, map[string]map[string]int64) {
	var allAnalysis []indexes.IndexAnalysis
	var scope analysisScope
	sizes := make(map[string]map[string]int64)

	colls := make([]string, len(collections))
	copy(colls, collections)

	shardKeys, err := indexes.CollectShardKeys(ctx, client)
	if err != nil {
		if indexes.ConnectedToMongos(ctx, client) {
			log.Warnf("cannot read the shard keys, so indexes that support a shard key are not protected: %s", err)
		} else {
			log.Debugf("cannot read the shard keys: %s", err)
		}
	}

	for _, database := range databases {
		if indexes.IsSystemDB(database) {
			continue
		}

		if len(collections) == 0 {
			colls, err = indexes.CollectionNames(ctx, client, database)
			if err != nil {
				log.Errorf("cannot get the list of collections for the database %s: %s", database, err)
				continue
			}
		}

		analysed := 0

		for _, collection := range colls {
			if indexes.IsSystemCollection(collection) {
				continue
			}

			ns := database + "." + collection

			log.Debugf("analyze-unused start namespace=%s", ns)

			stats, err := indexes.CollectIndexStats(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error collecting $indexStats for %s: %s", ns, err)
				continue
			}
			stats = indexes.AggregateShardStats(stats)
			if len(stats) == 0 {
				continue
			}

			metadata, err := indexes.CollectIndexMetadata(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error collecting index metadata for %s: %s", ns, err)
				continue
			}

			cs, err := indexes.CollectDocCount(ctx, client, database, collection)
			if err != nil {
				log.Warnf("cannot count the documents in %s: %s", ns, err)
			}

			build := func() []indexes.IndexRecord {
				records := indexes.DeduplicateIndexRecords(indexes.BuildIndexRecords(stats, metadata, cs, ns))
				indexes.MarkShardKeyIndexes(records, shardKeys[ns])
				if cfg.CrossReferenceDuplicates && duplicates != nil {
					indexes.CrossReferenceDuplicates(records, duplicates, stats)
				}
				return records
			}

			records := build()
			if len(records) == 0 {
				continue
			}

			if needsSizes(indexes.ScoreRecords(records, cfg)) {
				full, err := indexes.CollectCollStats(ctx, client, database, collection)
				if err != nil {
					log.Warnf("cannot get collStats for %s (sizes will be 0): %s", ns, err)
				} else {
					cs = full
					records = build()
					sizes[ns] = full.IndexSizes
				}
			}

			analysed++
			scope.Collections++
			scope.Indexes += len(records)
			for _, r := range records {
				if !r.AccessSince.IsZero() && (scope.OldestSince.IsZero() || r.AccessSince.Before(scope.OldestSince)) {
					scope.OldestSince = r.AccessSince
				}
			}

			log.Debugf("analyze-unused done namespace=%s indexStats=%d metadata=%d records=%d",
				ns, len(stats), len(metadata), len(records))

			allAnalysis = append(allAnalysis, indexes.ScoreRecords(records, cfg)...)
		}

		if analysed > 0 {
			scope.Databases++
		}
	}

	return allAnalysis, scope, sizes
}

func findDuplicated(ctx context.Context, client *mongo.Client, databases []string, collections []string) ([]indexes.Duplicate, []indexes.SkippedDuplicate) {
	duplicated := []indexes.Duplicate{}
	var skipped []indexes.SkippedDuplicate
	var err error

	colls := make([]string, len(collections))
	copy(colls, collections)

	for _, database := range databases {
		if indexes.IsSystemDB(database) {
			continue
		}

		if len(collections) == 0 {
			colls, err = indexes.CollectionNames(ctx, client, database)
			if err != nil {
				log.Errorf("cannot get the list of collections for the database %s: %s", database, err)
				continue
			}
		}

		for _, collection := range colls {
			if indexes.IsSystemCollection(collection) {
				continue
			}

			log.Debugf("check-duplicates start namespace=%s.%s", database, collection)

			dups, skips, err := indexes.FindDuplicated(ctx, client, database, collection)
			if err != nil {
				log.Errorf("error while checking duplicated indexes in %s.%s: %s", database, collection, err)
				continue
			}

			log.Debugf("check-duplicates done namespace=%s.%s duplicate-groups=%d", database, collection, len(dups))

			duplicated = append(duplicated, dups...)
			skipped = append(skipped, skips...)
		}
	}

	return duplicated, skipped
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
