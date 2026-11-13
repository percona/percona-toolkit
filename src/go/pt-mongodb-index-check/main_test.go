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
	"os/exec"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson/primitive"

	"github.com/percona/percona-toolkit/src/go/pt-mongodb-index-check/indexes"
)

// semVerRE is the SemVer pattern from https://semver.org (RE2-compatible
// variant), used to validate the version line printed by --version.
const semVerRE = `(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)` +
	`(?:-(?:(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?` +
	`(?:\+(?:[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?`

/*
Option --version
*/
func TestVersionOption(t *testing.T) {
	out, err := exec.Command("../../../bin/"+toolname, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(toolname + `\n.*Version v?` + semVerRE + `\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", toolname, out)
	}
}

func TestExtractDBFromURI(t *testing.T) {
	tests := []struct {
		uri  string
		want string
	}{
		{"mongodb://localhost:27017/mydb", "mydb"},
		{"mongodb://localhost:27017/admin", ""},
		{"mongodb://localhost:27017", ""},
		{"mongodb://localhost:27017/", ""},
		{"mongodb://user:pass@host:27017/testdb?authSource=admin", "testdb"},
		{"mongodb+srv://host/appdb", "appdb"},
		{"not-a-valid-uri", ""},
	}

	for _, tt := range tests {
		t.Run(tt.uri, func(t *testing.T) {
			got := extractDBFromURI(tt.uri)
			if got != tt.want {
				t.Errorf("extractDBFromURI(%q) = %q, want %q", tt.uri, got, tt.want)
			}
		})
	}
}

func TestRedactMongoURI(t *testing.T) {
	tests := []struct {
		in   string
		want string // substring checks unless full is set via containsOnly
	}{
		{
			in:   "mongodb://user:secret@host:27017/mydb?authSource=admin",
			want: "mongodb://user:xxx@host:27017/mydb?authSource=admin",
		},
		{
			in:   "mongodb://host:27017/mydb",
			want: "mongodb://host:27017/mydb",
		},
		{
			in:   "mongodb+srv://u:p%40ssword@cluster.example/dbname",
			want: "mongodb+srv://u:xxx@cluster.example/dbname",
		},
		{
			in:   "mongodb://onlyuser@host:27017/",
			want: "mongodb://onlyuser@host:27017/",
		},
	}

	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got := redactMongoURI(tt.in)
			if got != tt.want {
				t.Errorf("redactMongoURI(%q) = %q, want %q", tt.in, got, tt.want)
			}
			if strings.Contains(got, "secret") || strings.Contains(got, "p%40ssword") {
				t.Errorf("redactMongoURI leaked credential in %q", got)
			}
		})
	}
}

func TestRedactMongoURI_invalid(t *testing.T) {
	if g := redactMongoURI("://"); g != "<unparsable-uri>" {
		t.Errorf("expected unparsable sentinel, got %q", g)
	}
}

func TestBuildDuplicateReportData(t *testing.T) {
	t.Run("empty", func(t *testing.T) {
		d := buildDuplicateReportData(nil, nil)
		assert.Equal(t, 0, d.TotalPairs)
		assert.Empty(t, d.Standard)
		assert.Empty(t, d.WithWarning)
		assert.Equal(t, 0, d.DatabaseCount)
		assert.Equal(t, 0, d.CollectionCount)
	})

	t.Run("partition standard vs warning and action", func(t *testing.T) {
		dups := []indexes.Duplicate{
			{
				Namespace:     "mydb.orders",
				Name:          "idx_a",
				Key:           indexes.IndexKey{{Key: "a", Value: int32(1)}},
				ContainerName: "idx_ab",
				ContainerKey: indexes.IndexKey{
					{Key: "a", Value: int32(1)},
					{Key: "b", Value: int32(1)},
				},
			},
			{
				Namespace:     "mydb.users",
				Name:          "email_1",
				Key:           indexes.IndexKey{{Key: "email", Value: int32(1)}},
				ContainerName: "email_status",
				ContainerKey: indexes.IndexKey{
					{Key: "email", Value: int32(1)},
					{Key: "status", Value: int32(1)},
				},
				Warning:    "prefix index enforces unique constraint",
				Constraint: "unique",
			},
		}
		sizes := map[string]map[string]int64{
			"mydb.orders": {"idx_a": 100, "idx_ab": 500},
			"mydb.users":  {"email_1": 50, "email_status": 200},
		}
		d := buildDuplicateReportData(dups, sizes)
		assert.Equal(t, 2, d.TotalPairs)
		assert.Equal(t, 1, d.DatabaseCount, "distinct database prefix")
		assert.Equal(t, 2, d.CollectionCount, "distinct namespaces")
		assert.Len(t, d.Standard, 1)
		assert.Len(t, d.WithWarning, 1)
		assert.Contains(t, d.Standard[0].Action, `dropIndex("idx_a")`)
		assert.Contains(t, d.Standard[0].Action, "db.orders.")
		assert.True(t, d.Standard[0].HasSizes)
		assert.Equal(t, int64(100), d.Standard[0].PrefixSize)
		assert.Equal(t, int64(500), d.Standard[0].ContainerSize)
		assert.Contains(t, d.Standard[0].Reason, "idx_a")
		assert.Contains(t, d.Standard[0].Reason, "idx_ab")
		assert.Equal(t, "prefix index enforces unique constraint", d.WithWarning[0].Warning)
		assert.Equal(t, "[UNIQUE]", d.WithWarning[0].Tag)
		assert.Empty(t, d.WithWarning[0].Action)
	})

	t.Run("nil size map omits sizes", func(t *testing.T) {
		d := buildDuplicateReportData([]indexes.Duplicate{
			{
				Namespace:     "app.coll",
				Name:          "x_1",
				Key:           indexes.IndexKey{{Key: "x", Value: int32(1)}},
				ContainerName: "x_y",
				ContainerKey:  indexes.IndexKey{{Key: "x", Value: int32(1)}, {Key: "y", Value: int32(-1)}},
			},
		}, nil)
		assert.Len(t, d.Standard, 1)
		assert.False(t, d.Standard[0].HasSizes)
	})
}

func TestRenderDuplicateReport_containsSections(t *testing.T) {
	data := buildDuplicateReportData([]indexes.Duplicate{
		{
			Namespace:     "shop.orders",
			Name:          "region_1",
			Key:           indexes.IndexKey{{Key: "region", Value: int32(1)}},
			ContainerName: "region_created",
			ContainerKey: indexes.IndexKey{
				{Key: "region", Value: int32(1)},
				{Key: "created", Value: int32(-1)},
			},
		},
	}, nil)

	buf := new(bytes.Buffer)
	renderDuplicateReport(buf, data)
	out := buf.String()
	assert.Contains(t, out, "Duplicate Prefix Index Report")
	assert.Contains(t, out, "REDUNDANT PREFIX")
	assert.Contains(t, out, "shop.orders")
	assert.Contains(t, out, "dropIndex(\"region_1\")")
	assert.Contains(t, out, "Summary:")
}

// Regression: unique prefix warning must appear in rendered duplicate report
func TestRenderDuplicateReport_uniqueWarning(t *testing.T) {
	data := buildDuplicateReportData([]indexes.Duplicate{
		{
			Namespace:     "mydb.users",
			Name:          "email_unique",
			Key:           indexes.IndexKey{{Key: "email", Value: int32(1)}},
			ContainerName: "email_status",
			ContainerKey: indexes.IndexKey{
				{Key: "email", Value: int32(1)},
				{Key: "status", Value: int32(1)},
			},
			Warning:    "the prefix index enforces uniqueness on its own fields; the container cannot, so dropping it loses the unique constraint",
			Constraint: "unique",
		},
		{
			Namespace:     "mydb.sessions",
			Name:          "expires_1",
			Key:           indexes.IndexKey{{Key: "expires", Value: int32(1)}},
			ContainerName: "expires_1_user_1",
			ContainerKey: indexes.IndexKey{
				{Key: "expires", Value: int32(1)},
				{Key: "user", Value: int32(1)},
			},
			Warning:    "the prefix index is a TTL index; dropping it stops document expiry",
			Constraint: "TTL",
		},
	}, nil)

	buf := new(bytes.Buffer)
	renderDuplicateReport(buf, data)
	out := buf.String()
	assert.Contains(t, out, "PREFIX ENFORCES A CONSTRAINT (keep it)")
	assert.Contains(t, out, "{email:1}  [UNIQUE]")
	assert.Contains(t, out, "{expires:1}  [TTL]")
	assert.Contains(t, out, "WARNING: the prefix index is a TTL index; dropping it stops document expiry")
	assert.NotContains(t, out, "dropIndex")
	assert.NotContains(t, out, "Reason:")
	assert.Contains(t, out, "# Summary: 0 redundant prefix pair(s), 2 pair(s) kept for a constraint")
	assert.Empty(t, data.Standard, "constraint pairs should not be in Standard section")
	assert.Len(t, data.WithWarning, 2)
}

// Regression: check-unused output must NOT include the duplicate report section
func TestOutput_checkUnused_noDuplicateSection(t *testing.T) {
	resp := response{}
	analysis := []indexes.IndexAnalysis{
		{
			Namespace:      "mydb.orders",
			IndexName:      "idx_old",
			IndexKey:       primitive.D{{Key: "old", Value: int32(1)}},
			Recommendation: indexes.RecommendMonitor,
			Reason:         "test reason",
		},
	}
	out := output(resp, false, analysis, analysisScope{Databases: 1, Collections: 1}, duplicateReportData{}, false, true)
	assert.NotContains(t, out, "Duplicate Prefix Index Report")
	assert.Contains(t, out, "Unused Index Analysis")
}

// Regression: check-all output must include BOTH duplicate and unused sections
func TestOutput_checkAll_bothSections(t *testing.T) {
	dups := []indexes.Duplicate{
		{
			Namespace:     "mydb.orders",
			Name:          "idx_a",
			Key:           indexes.IndexKey{{Key: "a", Value: int32(1)}},
			ContainerName: "idx_ab",
			ContainerKey: indexes.IndexKey{
				{Key: "a", Value: int32(1)},
				{Key: "b", Value: int32(1)},
			},
		},
	}
	dupReport := buildDuplicateReportData(dups, nil)
	resp := response{Duplicated: dups}
	analysis := []indexes.IndexAnalysis{
		{
			Namespace:      "mydb.orders",
			IndexName:      "idx_test",
			IndexKey:       primitive.D{{Key: "test", Value: int32(1)}},
			Recommendation: indexes.RecommendMonitor,
			Reason:         "monitoring",
		},
	}
	out := output(resp, false, analysis, analysisScope{Databases: 1, Collections: 1}, dupReport, true, true)
	assert.Contains(t, out, "Duplicate Prefix Index Report")
	assert.Contains(t, out, "Unused Index Analysis")
	assert.Contains(t, out, `dropIndex("idx_a")`)
}

// Regression: no database selected must produce an error, not blank output
func TestExtractDBFromURI_adminReturnsEmpty(t *testing.T) {
	assert.Equal(t, "", extractDBFromURI("mongodb://localhost:27017/admin"))
	assert.Equal(t, "", extractDBFromURI("mongodb://localhost:27017"))
	assert.Equal(t, "", extractDBFromURI("mongodb://localhost:27017/"))
	assert.Equal(t, "", extractDBFromURI("not-a-uri"))
}

func TestPtdebugEnabled(t *testing.T) {
	t.Run("off when unset", func(t *testing.T) {
		t.Setenv("PTDEBUG", "")
		if ptdebugEnabled() {
			t.Fatal("expected false when PTDEBUG empty")
		}
	})
	t.Run("off for zero", func(t *testing.T) {
		t.Setenv("PTDEBUG", "0")
		if ptdebugEnabled() {
			t.Fatal("expected false when PTDEBUG=0")
		}
	})
	t.Run("on for one", func(t *testing.T) {
		t.Setenv("PTDEBUG", "1")
		if !ptdebugEnabled() {
			t.Fatal("expected true when PTDEBUG=1")
		}
	})
}

func TestNoCommand(t *testing.T) {
	mockMongo := "mongodb://127.0.0.1:27017"
	out, err := exec.Command("../../../bin/"+toolname, "--mongodb.uri", mockMongo).Output()
	if err != nil {
		t.Errorf("error executing %s with no command: %s", toolname, err.Error())
	}

	want := "Usage: pt-mongodb-index-check show-help"
	if !strings.Contains(string(out), want) {
		t.Errorf("Output missmatch. Output %q should contain %q", string(out), want)
	}
}

func TestRenderDuplicateReport_skipped(t *testing.T) {
	data := buildDuplicateReportData(nil, nil)
	data.Skipped = []indexes.SkippedDuplicate{
		{Namespace: "db.people", Name: "name_1", ContainerName: "name_1_surname_1", Reason: "partialFilterExpression differs"},
	}

	buf := new(bytes.Buffer)
	renderDuplicateReport(buf, data)
	out := buf.String()
	assert.Contains(t, out, "# No duplicate prefix indexes detected.")
	assert.Contains(t, out, "# ---- NOT REPORTED (key prefix, but index options differ) -----\n")
	assert.Contains(t, out, "  db.people  'name_1' is a key prefix of 'name_1_surname_1', but partialFilterExpression differs\n")
}

func TestOutput_noServerWriteRate(t *testing.T) {
	analysis := []indexes.IndexAnalysis{{
		Namespace: "db.c", IndexName: "x_1", Recommendation: indexes.RecommendLowUsage,
		Reason: "Index used 0.5 times/day; consider monitoring",
	}}

	text := output(response{Analysis: analysis}, false, analysis, analysisScope{Databases: 1, Collections: 1}, duplicateReportData{}, false, true)
	assert.NotContains(t, text, "write rate")

	js := output(response{Analysis: analysis}, true, analysis, analysisScope{Databases: 1, Collections: 1}, duplicateReportData{}, false, true)
	assert.NotContains(t, js, "writeOpsPerSec")
}

func TestOutput_noAnalysis(t *testing.T) {
	out := output(response{}, false, nil, analysisScope{Databases: 1, Collections: 2}, buildDuplicateReportData(nil, nil), true, false)
	assert.Contains(t, out, "Duplicate Prefix Index Report")
	assert.NotContains(t, out, "Unused")

	since := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	out = output(response{}, false, nil, analysisScope{Databases: 1, Collections: 2, Indexes: 3, OldestSince: since},
		duplicateReportData{}, false, true)
	assert.Contains(t, out, "# Observation window: 2026-01-01T00:00:00Z to ")
	assert.Contains(t, out, "# Indexes analyzed: 3 across 1 database(s), 2 collection(s)")
	assert.Contains(t, out, "# No unused index candidates found.")
	assert.NotContains(t, out, "since last restart")

	out = output(response{}, false, nil, analysisScope{Databases: 1, Collections: 2}, duplicateReportData{}, false, true)
	assert.NotContains(t, out, "No unused index candidates found.")
}

func TestTimeoutFlag(t *testing.T) {
	start := time.Now()
	out, err := exec.Command("../../../bin/"+toolname, "check-all", "--databases=test", "--timeout=1ms",
		"--mongodb.uri=mongodb://127.0.0.1:1").CombinedOutput()
	require.Error(t, err)
	assert.Contains(t, string(out), "context deadline exceeded")
	assert.Less(t, time.Since(start), 10*time.Second)

	out, err = exec.Command("../../../bin/"+toolname, "check-all", "--databases=test", "--timeout=0s",
		"--mongodb.uri=mongodb://127.0.0.1:1").CombinedOutput()
	require.Error(t, err)
	assert.Contains(t, string(out), "--timeout must be greater than 0")
}

func TestConnectionErrorHidesPassword(t *testing.T) {
	out, err := exec.Command("../../../bin/"+toolname, "check-all", "--databases=test", "--timeout=1ms",
		"--mongodb.uri=mongodb://user:secret@127.0.0.1:1").CombinedOutput()
	require.Error(t, err)
	assert.Contains(t, string(out), "Cannot connect to MongoDB at mongodb://user:xxx@127.0.0.1:1")
	assert.NotContains(t, string(out), "secret")
}
