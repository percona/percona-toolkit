package indexes

import (
	"fmt"
	"math"
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

const (
	RecommendSafeToDrop    = "SAFE_TO_DROP"
	RecommendLikelyUnused  = "LIKELY_UNUSED"
	RecommendMonitor       = "MONITOR"
	RecommendLowUsage      = "LOW_USAGE"
	RecommendKeepConstraint = "KEEP_CONSTRAINT"
	RecommendKeepHidden    = "KEEP_HIDDEN"
	RecommendKeepPartial   = "KEEP_PARTIAL"

	ConfidenceHigh   = "high"
	ConfidenceMedium = "medium"
	ConfidenceLow    = "low"

	DefaultWarmupDays        = 7
	DefaultLowUsageThreshold = 1.0
	DefaultLargeIndexSize    = 10 * 1024 * 1024 // 10 MB
)

// AnalysisConfig holds configurable thresholds for index analysis.
type AnalysisConfig struct {
	WarmupDays             float64
	LowUsageThreshold      float64
	LargeIndexSizeBytes    int64
	IncludeLowUsage        bool
	CrossReferenceDuplicates bool
	Now                    time.Time
}

// DefaultAnalysisConfig returns the default configuration.
func DefaultAnalysisConfig() AnalysisConfig {
	return AnalysisConfig{
		WarmupDays:             DefaultWarmupDays,
		LowUsageThreshold:      DefaultLowUsageThreshold,
		LargeIndexSizeBytes:    DefaultLargeIndexSize,
		IncludeLowUsage:        false,
		CrossReferenceDuplicates: true,
		Now:                    time.Now(),
	}
}

// IndexAnalysis holds the full analysis result for a single index.
type IndexAnalysis struct {
	Namespace        string      `json:"namespace"`
	IndexName        string      `json:"indexName"`
	IndexKey         primitive.D `json:"indexKey"`

	AccessOps   int64     `json:"accessOps"`
	AccessSince time.Time `json:"accessSince"`

	AgeDays          float64 `json:"ageDays"`
	OpsPerDay        float64 `json:"opsPerDay"`
	IndexSizeBytes   int64   `json:"indexSizeBytes"`
	CollDocCount     int64   `json:"collDocCount"`
	CollTotalIdxSize int64   `json:"collTotalIdxSize"`
	IndexSizePct     float64 `json:"indexSizePct"`

	IsPartial bool `json:"isPartial"`
	IsSparse  bool `json:"isSparse"`
	IsUnique  bool `json:"isUnique"`
	IsTTL     bool `json:"isTTL"`
	IsHidden  bool `json:"isHidden"`

	WriteOpsPerSec float64 `json:"writeOpsPerSec"`

	Score          float64 `json:"score"`
	Recommendation string  `json:"recommendation"`
	Confidence     string  `json:"confidence"`
	Reason         string  `json:"reason"`
}

// IndexRecord is the merged data collected from multiple MongoDB commands
// before scoring. It is the input to ScoreIndex.
type IndexRecord struct {
	Namespace  string
	IndexName  string
	IndexKey   primitive.D

	AccessOps   int64
	AccessSince time.Time

	IndexSizeBytes   int64
	CollDocCount     int64
	CollTotalIdxSize int64

	IsPartial bool
	IsSparse  bool
	IsUnique  bool
	IsTTL     bool
	IsHidden  bool

	WriteOpsPerSec float64

	// Set by cross-reference with duplicate check results
	IsDuplicatePrefix       bool
	DuplicateContainerName  string
	DuplicateContainerOps   int64
}

// ScoreIndex evaluates an IndexRecord against the scoring decision tree
// and returns an IndexAnalysis with the verdict populated.
func ScoreIndex(rec IndexRecord, cfg AnalysisConfig) IndexAnalysis {
	now := cfg.Now
	if now.IsZero() {
		now = time.Now()
	}

	ageDays := now.Sub(rec.AccessSince).Hours() / 24
	if ageDays < 0 {
		ageDays = 0
	}

	var opsPerDay float64
	if ageDays > 0 {
		opsPerDay = float64(rec.AccessOps) / ageDays
	}

	var indexSizePct float64
	if rec.CollTotalIdxSize > 0 {
		indexSizePct = float64(rec.IndexSizeBytes) / float64(rec.CollTotalIdxSize) * 100
	}

	a := IndexAnalysis{
		Namespace:        rec.Namespace,
		IndexName:        rec.IndexName,
		IndexKey:         rec.IndexKey,
		AccessOps:        rec.AccessOps,
		AccessSince:      rec.AccessSince,
		AgeDays:          math.Round(ageDays*10) / 10,
		OpsPerDay:        math.Round(opsPerDay*10) / 10,
		IndexSizeBytes:   rec.IndexSizeBytes,
		CollDocCount:     rec.CollDocCount,
		CollTotalIdxSize: rec.CollTotalIdxSize,
		IndexSizePct:     math.Round(indexSizePct*10) / 10,
		IsPartial:        rec.IsPartial,
		IsSparse:         rec.IsSparse,
		IsUnique:         rec.IsUnique,
		IsTTL:            rec.IsTTL,
		IsHidden:         rec.IsHidden,
		WriteOpsPerSec:   rec.WriteOpsPerSec,
	}

	// Hard guards
	if rec.IndexName == "_id_" {
		a.Score = 0
		a.Recommendation = RecommendKeepConstraint
		a.Confidence = ConfidenceHigh
		a.Reason = "MongoDB required _id_ index"
		return a
	}
	if rec.IsUnique {
		a.Score = 0
		a.Recommendation = RecommendKeepConstraint
		a.Confidence = ConfidenceHigh
		a.Reason = "enforces uniqueness constraint"
		return a
	}
	if rec.IsTTL {
		a.Score = 0
		a.Recommendation = RecommendKeepConstraint
		a.Confidence = ConfidenceHigh
		a.Reason = "TTL index for automatic document expiration"
		return a
	}
	if rec.IsHidden {
		a.Score = 0
		a.Recommendation = RecommendKeepHidden
		a.Confidence = ConfidenceHigh
		a.Reason = "intentionally excluded from query planner by admin"
		return a
	}

	// Warmup period check
	if ageDays < cfg.WarmupDays {
		a.Score = 0.1
		a.Recommendation = RecommendMonitor
		a.Confidence = ConfidenceLow
		a.Reason = fmt.Sprintf("Index created/stats reset %.0f days ago; re-check after %.0f days",
			ageDays, cfg.WarmupDays)
		return a
	}

	// Cross-reference with duplicate check
	if cfg.CrossReferenceDuplicates && rec.IsDuplicatePrefix && rec.AccessOps == 0 && rec.DuplicateContainerOps > 0 {
		a.Score = 0.95
		a.Recommendation = RecommendSafeToDrop
		a.Confidence = ConfidenceHigh
		a.Reason = fmt.Sprintf("Prefix of '%s' which is actively used (%d ops); this shorter index is redundant",
			rec.DuplicateContainerName, rec.DuplicateContainerOps)
		return a
	}

	// Zero-access scoring
	if rec.AccessOps == 0 {
		if rec.IsPartial || rec.IsSparse {
			a.Score = 0.4
			a.Recommendation = RecommendKeepPartial
			a.Confidence = ConfidenceMedium
			a.Reason = "Partial/sparse indexes may legitimately have low access; verify the filter expression matches current query patterns"
			return a
		}
		if rec.CollDocCount == 0 {
			a.Score = 0.2
			a.Recommendation = RecommendMonitor
			a.Confidence = ConfidenceLow
			a.Reason = "Collection is empty; index cannot have been used"
			return a
		}
		if rec.IndexSizeBytes > cfg.LargeIndexSizeBytes {
			a.Score = 0.95
			a.Recommendation = RecommendSafeToDrop
			a.Confidence = ConfidenceHigh
			a.Reason = fmt.Sprintf("Zero reads in %.0f days; index is %s and costs write amplification",
			ageDays, FormatBytes(rec.IndexSizeBytes))
		return a
	}
	a.Score = 0.8
	a.Recommendation = RecommendLikelyUnused
	a.Confidence = ConfidenceHigh
	a.Reason = fmt.Sprintf("Zero reads in %.0f days; small index (%s), low cost to keep",
		ageDays, FormatBytes(rec.IndexSizeBytes))
		return a
	}

	// Low-usage scoring
	if opsPerDay < cfg.LowUsageThreshold {
		writesPerDay := math.Max(rec.WriteOpsPerSec*86400, 1)
		usageRatio := opsPerDay / writesPerDay

		if usageRatio < 0.0001 {
			a.Score = 0.7
			a.Recommendation = RecommendLowUsage
			a.Confidence = ConfidenceMedium
			a.Reason = fmt.Sprintf("Index used %.1f times/day on a collection with %.0f writes/day; read benefit negligible vs write cost",
				opsPerDay, writesPerDay)
			return a
		}
		a.Score = 0.5
		a.Recommendation = RecommendLowUsage
		a.Confidence = ConfidenceMedium
		a.Reason = fmt.Sprintf("Index used %.1f times/day; consider monitoring", opsPerDay)
		return a
	}

	// Index is actively used
	a.Score = 0
	a.Recommendation = ""
	a.Confidence = ""
	a.Reason = ""
	return a
}

func FormatBytes(b int64) string {
	const (
		kb = 1024
		mb = kb * 1024
		gb = mb * 1024
	)
	switch {
	case b >= gb:
		return fmt.Sprintf("%.1f GB", float64(b)/float64(gb))
	case b >= mb:
		return fmt.Sprintf("%.1f MB", float64(b)/float64(mb))
	case b >= kb:
		return fmt.Sprintf("%.1f KB", float64(b)/float64(kb))
	default:
		return fmt.Sprintf("%d B", b)
	}
}
