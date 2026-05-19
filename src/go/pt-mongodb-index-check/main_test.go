package main

import (
	"bytes"
	"os/exec"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson/primitive"

	"github.com/percona/percona-toolkit/src/go/pt-mongodb-index-check/indexes"
)

/*
Option --version
*/
func TestVersionOption(t *testing.T) {
	out, err := exec.Command("../../../bin/"+toolname, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(toolname + `\n.*Version v?\d+\.\d+\.\d+\n`)
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
	if g := redactMongoURI("://"); g != "<unparseable-uri>" {
		t.Errorf("expected unparseable sentinel, got %q", g)
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
				Warning: "prefix index enforces unique constraint",
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
		assert.Contains(t, d.WithWarning[0].Action, `dropIndex("email_1")`)
		assert.Contains(t, d.WithWarning[0].Action, "db.users.")
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
			Warning: "prefix index enforces unique constraint; dropping requires the container index to also be unique",
		},
	}, nil)

	buf := new(bytes.Buffer)
	renderDuplicateReport(buf, data)
	out := buf.String()
	assert.Contains(t, out, "UNIQUE / CONSTRAINT WARNING")
	assert.Contains(t, out, "[UNIQUE]")
	assert.Contains(t, out, "WARNING: prefix index enforces unique constraint")
	assert.Contains(t, out, `dropIndex("email_unique")`)
	assert.Empty(t, data.Standard, "unique pair should not be in Standard section")
	assert.Len(t, data.WithWarning, 1)
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
	out := output(resp, false, analysis, 1, 1, duplicateReportData{}, false)
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
	out := output(resp, false, analysis, 1, 1, dupReport, true)
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
