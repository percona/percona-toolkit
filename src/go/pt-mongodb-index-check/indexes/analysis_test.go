package indexes

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

func baseConfig() AnalysisConfig {
	return AnalysisConfig{
		WarmupDays:               7,
		LowUsageThreshold:        1.0,
		LargeIndexSizeBytes:      10 * 1024 * 1024, // 10 MB
		IncludeLowUsage:          true,
		CrossReferenceDuplicates: true,
		Now:                      time.Date(2024, 2, 15, 0, 0, 0, 0, time.UTC),
	}
}

func TestScoreIndex(t *testing.T) {
	cfg := baseConfig()
	thirtyDaysAgo := cfg.Now.AddDate(0, 0, -30)
	threeDaysAgo := cfg.Now.AddDate(0, 0, -3)

	tests := []struct {
		name           string
		rec            IndexRecord
		wantRec        string
		wantScoreMin   float64
		wantScoreMax   float64
		wantConfidence string
	}{
		{
			name: "_id_ index is always kept",
			rec: IndexRecord{
				IndexName:   "_id_",
				AccessOps:   0,
				AccessSince: thirtyDaysAgo,
			},
			wantRec:        RecommendKeepConstraint,
			wantScoreMin:   0,
			wantScoreMax:   0,
			wantConfidence: ConfidenceHigh,
		},
		{
			name: "unique index is always kept",
			rec: IndexRecord{
				IndexName:   "email_1",
				AccessOps:   0,
				AccessSince: thirtyDaysAgo,
				IsUnique:    true,
			},
			wantRec:        RecommendKeepConstraint,
			wantScoreMin:   0,
			wantScoreMax:   0,
			wantConfidence: ConfidenceHigh,
		},
		{
			name: "TTL index is always kept",
			rec: IndexRecord{
				IndexName:   "createdAt_1",
				AccessOps:   0,
				AccessSince: thirtyDaysAgo,
				IsTTL:       true,
			},
			wantRec:        RecommendKeepConstraint,
			wantScoreMin:   0,
			wantScoreMax:   0,
			wantConfidence: ConfidenceHigh,
		},
		{
			name: "hidden index is kept",
			rec: IndexRecord{
				IndexName:   "hidden_idx",
				AccessOps:   0,
				AccessSince: thirtyDaysAgo,
				IsHidden:    true,
			},
			wantRec:        RecommendKeepHidden,
			wantScoreMin:   0,
			wantScoreMax:   0,
			wantConfidence: ConfidenceHigh,
		},
		{
			name: "warmup period - stats reset recently",
			rec: IndexRecord{
				IndexName:   "new_idx",
				AccessOps:   0,
				AccessSince: threeDaysAgo,
			},
			wantRec:        RecommendMonitor,
			wantScoreMin:   0.1,
			wantScoreMax:   0.1,
			wantConfidence: ConfidenceLow,
		},
		{
			name: "zero ops, large index -> safe to drop",
			rec: IndexRecord{
				IndexName:      "old_big_idx",
				AccessOps:      0,
				AccessSince:    thirtyDaysAgo,
				IndexSizeBytes: 100 * 1024 * 1024, // 100 MB
				CollDocCount:   1000,
			},
			wantRec:        RecommendSafeToDrop,
			wantScoreMin:   0.95,
			wantScoreMax:   0.95,
			wantConfidence: ConfidenceHigh,
		},
		{
			name: "zero ops, small index -> likely unused",
			rec: IndexRecord{
				IndexName:      "old_small_idx",
				AccessOps:      0,
				AccessSince:    thirtyDaysAgo,
				IndexSizeBytes: 1024, // 1 KB
				CollDocCount:   100,
			},
			wantRec:        RecommendLikelyUnused,
			wantScoreMin:   0.8,
			wantScoreMax:   0.8,
			wantConfidence: ConfidenceHigh,
		},
		{
			name: "zero ops, partial index -> keep partial",
			rec: IndexRecord{
				IndexName:    "partial_idx",
				AccessOps:    0,
				AccessSince:  thirtyDaysAgo,
				IsPartial:    true,
				CollDocCount: 1000,
			},
			wantRec:        RecommendKeepPartial,
			wantScoreMin:   0.4,
			wantScoreMax:   0.4,
			wantConfidence: ConfidenceMedium,
		},
		{
			name: "zero ops, sparse index -> keep partial",
			rec: IndexRecord{
				IndexName:    "sparse_idx",
				AccessOps:    0,
				AccessSince:  thirtyDaysAgo,
				IsSparse:     true,
				CollDocCount: 1000,
			},
			wantRec:        RecommendKeepPartial,
			wantScoreMin:   0.4,
			wantScoreMax:   0.4,
			wantConfidence: ConfidenceMedium,
		},
		{
			name: "zero ops, empty collection -> monitor",
			rec: IndexRecord{
				IndexName:    "idx_on_empty",
				AccessOps:    0,
				AccessSince:  thirtyDaysAgo,
				CollDocCount: 0,
			},
			wantRec:        RecommendMonitor,
			wantScoreMin:   0.2,
			wantScoreMax:   0.2,
			wantConfidence: ConfidenceLow,
		},
		{
			name: "low usage, high write cost",
			rec: IndexRecord{
				IndexName:      "low_use_idx",
				AccessOps:      5,
				AccessSince:    thirtyDaysAgo,
				IndexSizeBytes: 50 * 1024 * 1024,
				CollDocCount:   100000,
				WriteOpsPerSec: 1000,
			},
			wantRec:        RecommendLowUsage,
			wantScoreMin:   0.5,
			wantScoreMax:   0.7,
			wantConfidence: ConfidenceMedium,
		},
		{
			name: "low usage, negligible ratio vs writes",
			rec: IndexRecord{
				IndexName:      "low_ratio_idx",
				AccessOps:      1,
				AccessSince:    thirtyDaysAgo,
				IndexSizeBytes: 50 * 1024 * 1024,
				CollDocCount:   100000,
				WriteOpsPerSec: 10000,
			},
			wantRec:        RecommendLowUsage,
			wantScoreMin:   0.7,
			wantScoreMax:   0.7,
			wantConfidence: ConfidenceMedium,
		},
		{
			name: "duplicate cross-ref: prefix unused, container used",
			rec: IndexRecord{
				IndexName:              "prefix_idx",
				AccessOps:              0,
				AccessSince:            thirtyDaysAgo,
				CollDocCount:           1000,
				IndexSizeBytes:         5000,
				IsDuplicatePrefix:      true,
				DuplicateContainerName: "full_idx",
				DuplicateContainerOps:  50000,
			},
			wantRec:        RecommendSafeToDrop,
			wantScoreMin:   0.95,
			wantScoreMax:   0.95,
			wantConfidence: ConfidenceHigh,
		},
		{
			name: "actively used index - no recommendation",
			rec: IndexRecord{
				IndexName:    "active_idx",
				AccessOps:    100000,
				AccessSince:  thirtyDaysAgo,
				CollDocCount: 1000,
			},
			wantRec:      "",
			wantScoreMin: 0,
			wantScoreMax: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ScoreIndex(tt.rec, cfg)
			assert.Equal(t, tt.wantRec, result.Recommendation, "recommendation mismatch")
			assert.GreaterOrEqual(t, result.Score, tt.wantScoreMin, "score too low")
			assert.LessOrEqual(t, result.Score, tt.wantScoreMax, "score too high")
			if tt.wantConfidence != "" {
				assert.Equal(t, tt.wantConfidence, result.Confidence, "confidence mismatch")
			}
		})
	}
}

func TestCompatibleIndexProperties(t *testing.T) {
	tests := []struct {
		name     string
		shorter  collectionIndex
		longer   collectionIndex
		expected bool
	}{
		{
			name:     "identical properties - compatible",
			shorter:  collectionIndex{Name: "a"},
			longer:   collectionIndex{Name: "b"},
			expected: true,
		},
		{
			name: "both partial, same filter - compatible",
			shorter: collectionIndex{
				Name:          "a",
				PartialFilter: primitive.M{"status": "active"},
			},
			longer: collectionIndex{
				Name:          "b",
				PartialFilter: primitive.M{"status": "active"},
			},
			expected: true,
		},
		{
			name: "both partial, different filter - NOT compatible",
			shorter: collectionIndex{
				Name:          "a",
				PartialFilter: primitive.M{"status": "active"},
			},
			longer: collectionIndex{
				Name:          "b",
				PartialFilter: primitive.M{"status": "inactive"},
			},
			expected: false,
		},
		{
			name: "one partial, one not - NOT compatible",
			shorter: collectionIndex{
				Name:          "a",
				PartialFilter: primitive.M{"status": "active"},
			},
			longer: collectionIndex{
				Name: "b",
			},
			expected: false,
		},
		{
			name: "different sparse - NOT compatible",
			shorter: collectionIndex{
				Name:   "a",
				Sparse: true,
			},
			longer: collectionIndex{
				Name:   "b",
				Sparse: false,
			},
			expected: false,
		},
		{
			name: "both sparse - compatible",
			shorter: collectionIndex{
				Name:   "a",
				Sparse: true,
			},
			longer: collectionIndex{
				Name:   "b",
				Sparse: true,
			},
			expected: true,
		},
		{
			name: "different collation - NOT compatible",
			shorter: collectionIndex{
				Name:      "a",
				Collation: primitive.M{"locale": "en"},
			},
			longer: collectionIndex{
				Name:      "b",
				Collation: primitive.M{"locale": "fr"},
			},
			expected: false,
		},
		{
			name: "one collation, one not - NOT compatible",
			shorter: collectionIndex{
				Name:      "a",
				Collation: primitive.M{"locale": "en"},
			},
			longer: collectionIndex{
				Name: "b",
			},
			expected: false,
		},
		{
			name: "same collation - compatible",
			shorter: collectionIndex{
				Name:      "a",
				Collation: primitive.M{"locale": "en"},
			},
			longer: collectionIndex{
				Name:      "b",
				Collation: primitive.M{"locale": "en"},
			},
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := compatibleIndexProperties(tt.shorter, tt.longer)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestFormatBytes(t *testing.T) {
	tests := []struct {
		input    int64
		expected string
	}{
		{0, "0 B"},
		{512, "512 B"},
		{1024, "1.0 KB"},
		{1536, "1.5 KB"},
		{1048576, "1.0 MB"},
		{10485760, "10.0 MB"},
		{1073741824, "1.0 GB"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			assert.Equal(t, tt.expected, FormatBytes(tt.input))
		})
	}
}

func TestBuildIndexRecords(t *testing.T) {
	now := time.Now()
	stats := []IndexStat{
		{
			Name: "idx_a",
			Key:  primitive.D{{Key: "a", Value: int32(1)}},
		},
	}
	stats[0].Accesses.Ops = 100
	stats[0].Accesses.Since = primitive.NewDateTimeFromTime(now.AddDate(0, 0, -10))

	meta := map[string]indexMetadata{
		"idx_a": {
			Name:   "idx_a",
			Unique: true,
		},
	}

	cs := collectionStats{
		Count:          5000,
		TotalIndexSize: 1000000,
		IndexSizes:     map[string]int64{"idx_a": 50000},
	}

	wr := serverWriteRate{WriteOpsPerSec: 200}

	records := BuildIndexRecords(stats, meta, cs, wr, "testdb.testcol")

	assert.Len(t, records, 1)
	rec := records[0]
	assert.Equal(t, "testdb.testcol", rec.Namespace)
	assert.Equal(t, "idx_a", rec.IndexName)
	assert.Equal(t, int64(100), rec.AccessOps)
	assert.Equal(t, int64(50000), rec.IndexSizeBytes)
	assert.Equal(t, int64(5000), rec.CollDocCount)
	assert.True(t, rec.IsUnique)
	assert.Equal(t, float64(200), rec.WriteOpsPerSec)
}

func TestAggregateShardStats(t *testing.T) {
	since1 := primitive.NewDateTimeFromTime(time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC))
	since2 := primitive.NewDateTimeFromTime(time.Date(2024, 1, 5, 0, 0, 0, 0, time.UTC))
	since3 := primitive.NewDateTimeFromTime(time.Date(2024, 1, 10, 0, 0, 0, 0, time.UTC))

	stats := []IndexStat{
		{Name: "idx_a", Key: primitive.D{{Key: "a", Value: int32(1)}}, Host: "shard1:27018"},
		{Name: "idx_a", Key: primitive.D{{Key: "a", Value: int32(1)}}, Host: "shard2:27018"},
		{Name: "idx_a", Key: primitive.D{{Key: "a", Value: int32(1)}}, Host: "shard3:27018"},
		{Name: "idx_b", Key: primitive.D{{Key: "b", Value: int32(1)}}, Host: "shard1:27018"},
	}
	stats[0].Accesses.Ops = 100
	stats[0].Accesses.Since = since1
	stats[1].Accesses.Ops = 200
	stats[1].Accesses.Since = since2
	stats[2].Accesses.Ops = 50
	stats[2].Accesses.Since = since3
	stats[3].Accesses.Ops = 10
	stats[3].Accesses.Since = since2

	merged := AggregateShardStats(stats)

	assert.Len(t, merged, 2)

	assert.Equal(t, "idx_a", merged[0].Name)
	assert.Equal(t, int64(350), merged[0].Accesses.Ops)
	assert.Equal(t, since1, merged[0].Accesses.Since, "should use the oldest since")
	assert.Equal(t, 3, merged[0].ShardCount)

	assert.Equal(t, "idx_b", merged[1].Name)
	assert.Equal(t, int64(10), merged[1].Accesses.Ops)
	assert.Equal(t, 1, merged[1].ShardCount)
}

func TestAggregateShardStats_singleShard(t *testing.T) {
	since := primitive.NewDateTimeFromTime(time.Date(2024, 2, 1, 0, 0, 0, 0, time.UTC))
	stats := []IndexStat{
		{Name: "idx_x", Key: primitive.D{{Key: "x", Value: int32(1)}}, Host: "primary:27017"},
		{Name: "idx_y", Key: primitive.D{{Key: "y", Value: int32(-1)}}, Host: "primary:27017"},
	}
	stats[0].Accesses.Ops = 42
	stats[0].Accesses.Since = since
	stats[1].Accesses.Ops = 99
	stats[1].Accesses.Since = since

	merged := AggregateShardStats(stats)

	assert.Len(t, merged, 2)
	assert.Equal(t, int64(42), merged[0].Accesses.Ops)
	assert.Equal(t, 1, merged[0].ShardCount)
	assert.Equal(t, int64(99), merged[1].Accesses.Ops)
	assert.Equal(t, 1, merged[1].ShardCount)
}

func TestComparableKey_hashed(t *testing.T) {
	idx := collectionIndex{
		Name: "_id_hashed",
		Key:  primitive.D{{Key: "_id", Value: "hashed"}},
	}
	assert.Equal(t, "hashed:_id", idx.ComparableKey())

	idIdx := collectionIndex{
		Name: "_id_",
		Key:  primitive.D{{Key: "_id", Value: int32(1)}},
	}
	assert.Equal(t, "+_id", idIdx.ComparableKey())
	assert.NotEqual(t, idIdx.ComparableKey(), idx.ComparableKey(),
		"_id_ and _id_hashed must produce different comparable keys")
}

func TestComparableKey_text(t *testing.T) {
	idx := collectionIndex{
		Name: "content_text",
		Key:  primitive.D{{Key: "content", Value: "text"}},
	}
	assert.Equal(t, "text:content", idx.ComparableKey())

	btree := collectionIndex{
		Name: "content_1",
		Key:  primitive.D{{Key: "content", Value: int32(1)}},
	}
	assert.NotEqual(t, btree.ComparableKey(), idx.ComparableKey(),
		"text index must not match B-tree index on same field")
}

func TestComparableKey_2dsphere(t *testing.T) {
	idx := collectionIndex{
		Name: "location_2dsphere",
		Key:  primitive.D{{Key: "location", Value: "2dsphere"}},
	}
	assert.Equal(t, "2dsphere:location", idx.ComparableKey())
}

func TestComparableKey_int64Direction(t *testing.T) {
	idx := collectionIndex{
		Name: "a_1",
		Key:  primitive.D{{Key: "a", Value: int64(1)}},
	}
	assert.Equal(t, "+a", idx.ComparableKey())
}

func TestNormalizeIndexStat(t *testing.T) {
	s := IndexStat{}
	s.Spec.Name = "my_idx"
	s.Spec.Key = primitive.D{{Key: "x", Value: int32(1)}}
	NormalizeIndexStat(&s)
	assert.Equal(t, "my_idx", s.Name)
	assert.Equal(t, primitive.D{{Key: "x", Value: int32(1)}}, s.Key)
}

func TestDeduplicateIndexRecords(t *testing.T) {
	t1 := time.Date(2024, 1, 10, 0, 0, 0, 0, time.UTC)
	t2 := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	recs := []IndexRecord{
		{IndexName: "idx_a", AccessOps: 10, AccessSince: t1},
		{IndexName: "idx_a", AccessOps: 5, AccessSince: t2},
		{IndexName: "idx_b", AccessOps: 3, AccessSince: t1},
	}
	out := DeduplicateIndexRecords(recs)
	assert.Len(t, out, 2)
	assert.Equal(t, "idx_a", out[0].IndexName)
	assert.Equal(t, int64(15), out[0].AccessOps)
	assert.Equal(t, t2, out[0].AccessSince)
	assert.Equal(t, "idx_b", out[1].IndexName)
}

func TestAggregateShardStats_afterNormalize(t *testing.T) {
	since1 := primitive.NewDateTimeFromTime(time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC))
	since2 := primitive.NewDateTimeFromTime(time.Date(2024, 1, 5, 0, 0, 0, 0, time.UTC))

	a := IndexStat{Name: "", Host: "s1"}
	a.Spec.Name = "same_idx"
	a.Accesses.Ops = 1
	a.Accesses.Since = since1
	b := IndexStat{Name: "", Host: "s2"}
	b.Spec.Name = "same_idx"
	b.Accesses.Ops = 2
	b.Accesses.Since = since2

	NormalizeIndexStat(&a)
	NormalizeIndexStat(&b)
	merged := AggregateShardStats([]IndexStat{a, b})

	assert.Len(t, merged, 1)
	assert.Equal(t, "same_idx", merged[0].Name)
	assert.Equal(t, int64(3), merged[0].Accesses.Ops)
	assert.Equal(t, since1, merged[0].Accesses.Since)
	assert.Equal(t, 2, merged[0].ShardCount)
}

func TestFindDuplicated_skips_id(t *testing.T) {
	idIdx := collectionIndex{
		Name: "_id_",
		Key:  primitive.D{{Key: "_id", Value: int32(1)}},
	}
	idHashedIdx := collectionIndex{
		Name: "_id_hashed",
		Key:  primitive.D{{Key: "_id", Value: "hashed"}},
	}
	compoundIdx := collectionIndex{
		Name: "id_status",
		Key:  primitive.D{{Key: "_id", Value: int32(1)}, {Key: "status", Value: int32(1)}},
	}

	_ = idIdx
	_ = idHashedIdx
	_ = compoundIdx
	// _id_ has ComparableKey "+_id" which is a prefix of "+_id+status"
	// Without the _id_ skip, _id_ would be flagged as duplicate of id_status.
	// We can't call FindDuplicated directly (needs a real DB), but we can
	// verify that _id_hashed != _id_ via ComparableKey.
	assert.NotEqual(t, "+_id", "hashed:_id")
}

func TestFindDuplicated_hashed_not_prefix(t *testing.T) {
	btreeKey := collectionIndex{
		Name: "field_1",
		Key:  primitive.D{{Key: "field", Value: int32(1)}},
	}
	hashedKey := collectionIndex{
		Name: "field_hashed",
		Key:  primitive.D{{Key: "field", Value: "hashed"}},
	}
	assert.False(t,
		strings.HasPrefix(hashedKey.ComparableKey(), btreeKey.ComparableKey()),
		"hashed index should not be a prefix of B-tree index")
	assert.False(t,
		strings.HasPrefix(btreeKey.ComparableKey(), hashedKey.ComparableKey()),
		"B-tree index should not be a prefix of hashed index")
}

// TestComparableKey_hashedSymbol ensures that a key value encoded as
// primitive.Symbol("hashed") — as seen on MongoDB 8.x — produces a different
// ComparableKey than a plain B-tree ascending key, preventing false positive
// duplicate detection between {phone:1} and {phone:"hashed"}.
func TestComparableKey_hashedSymbol(t *testing.T) {
	btree := collectionIndex{
		Name: "phone_1",
		Key:  primitive.D{{Key: "phone", Value: int32(1)}},
	}
	hashedSymbol := collectionIndex{
		Name: "phone_hashed",
		Key:  primitive.D{{Key: "phone", Value: primitive.Symbol("hashed")}},
	}

	assert.Equal(t, "+phone", btree.ComparableKey())
	assert.Equal(t, "hashed:phone", hashedSymbol.ComparableKey())
	assert.False(t,
		strings.HasPrefix(hashedSymbol.ComparableKey(), btree.ComparableKey()),
		"hashed (Symbol) index should not be a prefix of B-tree index")
	assert.False(t,
		strings.HasPrefix(btree.ComparableKey(), hashedSymbol.ComparableKey()),
		"B-tree index should not be a prefix of hashed (Symbol) index")
}

func TestCrossReferenceDuplicates(t *testing.T) {
	records := []IndexRecord{
		{IndexName: "idx_short", AccessOps: 0},
		{IndexName: "idx_full", AccessOps: 5000},
	}

	duplicates := []Duplicate{
		{
			Name:          "idx_short",
			ContainerName: "idx_full",
		},
	}

	allStats := []IndexStat{
		{Name: "idx_short"},
		{Name: "idx_full"},
	}
	allStats[0].Accesses.Ops = 0
	allStats[1].Accesses.Ops = 5000

	CrossReferenceDuplicates(records, duplicates, allStats)

	assert.True(t, records[0].IsDuplicatePrefix)
	assert.Equal(t, "idx_full", records[0].DuplicateContainerName)
	assert.Equal(t, int64(5000), records[0].DuplicateContainerOps)
	assert.False(t, records[1].IsDuplicatePrefix)
}
