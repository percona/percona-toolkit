package indexes

import (
	"context"

	"github.com/pkg/errors"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// indexMetadata holds index properties from listIndexes that $indexStats doesn't provide.
type indexMetadata struct {
	Name                    string      `bson:"name"`
	Key                     primitive.D `bson:"key"`
	Unique                  bool        `bson:"unique,omitempty"`
	Sparse                  bool        `bson:"sparse,omitempty"`
	PartialFilterExpression primitive.M `bson:"partialFilterExpression,omitempty"`
	ExpireAfterSeconds      *int32      `bson:"expireAfterSeconds,omitempty"`
	Hidden                  bool        `bson:"hidden,omitempty"`
}

type collectionStats struct {
	Count          int64            `bson:"count"`
	Size           int64            `bson:"size"`
	TotalIndexSize int64            `bson:"totalIndexSize"`
	IndexSizes     map[string]int64 `bson:"indexSizes"`
}

type serverWriteRate struct {
	WriteOpsPerSec float64
	Uptime         int64
}

// CollectIndexMetadata retrieves index properties from listIndexes for a collection.
func CollectIndexMetadata(ctx context.Context, client *mongo.Client, database, collection string) (map[string]indexMetadata, error) {
	cursor, err := client.Database(database).Collection(collection).Indexes().List(ctx, nil)
	if err != nil {
		return nil, errors.Wrap(err, "cannot list indexes")
	}

	result := make(map[string]indexMetadata)
	var indexes []indexMetadata
	if err := cursor.All(ctx, &indexes); err != nil {
		return nil, errors.Wrap(err, "cannot decode index metadata")
	}
	for _, idx := range indexes {
		result[idx.Name] = idx
	}
	return result, nil
}

// CollectCollStats retrieves collection statistics via the collStats command.
func CollectCollStats(ctx context.Context, client *mongo.Client, database, collection string) (collectionStats, error) {
	var stats collectionStats
	res := client.Database(database).RunCommand(ctx, bson.D{{Key: "collStats", Value: collection}})
	if err := res.Err(); err != nil {
		return stats, errors.Wrap(err, "cannot run collStats")
	}
	if err := res.Decode(&stats); err != nil {
		return stats, errors.Wrap(err, "cannot decode collStats")
	}
	return stats, nil
}

// CollectServerWriteRate retrieves the global write rate from serverStatus opcounters.
func CollectServerWriteRate(ctx context.Context, client *mongo.Client) (serverWriteRate, error) {
	var result struct {
		Uptime     int64 `bson:"uptime"`
		OpCounters struct {
			Insert int64 `bson:"insert"`
			Update int64 `bson:"update"`
			Delete int64 `bson:"delete"`
		} `bson:"opcounters"`
	}

	res := client.Database("admin").RunCommand(ctx, bson.D{{Key: "serverStatus", Value: 1}})
	if err := res.Err(); err != nil {
		return serverWriteRate{}, errors.Wrap(err, "cannot run serverStatus")
	}
	if err := res.Decode(&result); err != nil {
		return serverWriteRate{}, errors.Wrap(err, "cannot decode serverStatus")
	}

	totalWrites := result.OpCounters.Insert + result.OpCounters.Update + result.OpCounters.Delete
	var wps float64
	if result.Uptime > 0 {
		wps = float64(totalWrites) / float64(result.Uptime)
	}

	return serverWriteRate{
		WriteOpsPerSec: wps,
		Uptime:         result.Uptime,
	}, nil
}

// CollectIndexStats retrieves $indexStats for all indexes on a collection.
// Unlike FindUnused, this returns ALL indexes (not just ops==0) for the scoring engine.
func CollectIndexStats(ctx context.Context, client *mongo.Client, database, collection string) ([]IndexStat, error) {
	aggregation := mongo.Pipeline{
		{{Key: "$indexStats", Value: primitive.M{}}},
	}

	cursor, err := client.Database(database).Collection(collection).Aggregate(ctx, aggregation)
	if err != nil {
		return nil, errors.Wrap(err, "cannot run $indexStats")
	}

	var stats []IndexStat
	if err = cursor.All(ctx, &stats); err != nil {
		return nil, errors.Wrap(err, "cannot decode $indexStats")
	}
	for i := range stats {
		NormalizeIndexStat(&stats[i])
	}
	return stats, nil
}

// AggregateShardStats deduplicates $indexStats entries that appear once per
// shard on sharded clusters. It groups by index name, sums ops across shards,
// and uses the oldest accesses.since as the observation window.
func AggregateShardStats(stats []IndexStat) []IndexStat {
	type group struct {
		merged IndexStat
		count  int
	}

	groups := make(map[string]*group, len(stats))
	order := make([]string, 0, len(stats))

	for _, s := range stats {
		g, ok := groups[s.Name]
		if !ok {
			merged := s
			merged.ShardCount = 1
			groups[s.Name] = &group{merged: merged, count: 1}
			order = append(order, s.Name)
			continue
		}
		g.count++
		g.merged.ShardCount = g.count
		g.merged.Accesses.Ops += s.Accesses.Ops
		if s.Accesses.Since < g.merged.Accesses.Since {
			g.merged.Accesses.Since = s.Accesses.Since
		}
	}

	result := make([]IndexStat, 0, len(groups))
	for _, name := range order {
		result = append(result, groups[name].merged)
	}
	return result
}

// DeduplicateIndexRecords merges duplicate rows for the same index name (e.g.
// if stats were not aggregated) by summing ops and using the oldest AccessSince.
func DeduplicateIndexRecords(records []IndexRecord) []IndexRecord {
	if len(records) <= 1 {
		return records
	}
	byName := make(map[string]IndexRecord, len(records))
	order := make([]string, 0, len(records))
	for _, r := range records {
		prev, ok := byName[r.IndexName]
		if !ok {
			byName[r.IndexName] = r
			order = append(order, r.IndexName)
			continue
		}
		prev.AccessOps += r.AccessOps
		if !r.AccessSince.IsZero() && (prev.AccessSince.IsZero() || r.AccessSince.Before(prev.AccessSince)) {
			prev.AccessSince = r.AccessSince
		}
		byName[r.IndexName] = prev
	}
	out := make([]IndexRecord, 0, len(order))
	for _, name := range order {
		out = append(out, byName[name])
	}
	return out
}

// BuildIndexRecords merges data from $indexStats, listIndexes, collStats, and
// serverStatus into a slice of IndexRecord ready for scoring.
func BuildIndexRecords(
	stats []IndexStat,
	metadata map[string]indexMetadata,
	cs collectionStats,
	wr serverWriteRate,
	namespace string,
) []IndexRecord {
	records := make([]IndexRecord, 0, len(stats))

	for _, s := range stats {
		rec := IndexRecord{
			Namespace:        namespace,
			IndexName:        s.Name,
			IndexKey:         s.Key,
			AccessOps:        s.Accesses.Ops,
			AccessSince:      s.Accesses.Since.Time(),
			CollDocCount:     cs.Count,
			CollTotalIdxSize: cs.TotalIndexSize,
			WriteOpsPerSec:   wr.WriteOpsPerSec,
		}

		if size, ok := cs.IndexSizes[s.Name]; ok {
			rec.IndexSizeBytes = size
		}

		if meta, ok := metadata[s.Name]; ok {
			rec.IsPartial = len(meta.PartialFilterExpression) > 0
			rec.IsSparse = meta.Sparse
			rec.IsUnique = meta.Unique
			rec.IsTTL = meta.ExpireAfterSeconds != nil
			rec.IsHidden = meta.Hidden
		}

		records = append(records, rec)
	}

	return records
}

// CrossReferenceDuplicates annotates IndexRecords with duplicate prefix
// information by looking up each record in the duplicate results.
func CrossReferenceDuplicates(records []IndexRecord, duplicates []Duplicate, allStats []IndexStat) {
	opsMap := make(map[string]int64, len(allStats))
	for _, s := range allStats {
		opsMap[s.Name] += s.Accesses.Ops
	}

	dupMap := make(map[string]Duplicate, len(duplicates))
	for _, d := range duplicates {
		dupMap[d.Name] = d
	}

	for i := range records {
		if dup, ok := dupMap[records[i].IndexName]; ok {
			records[i].IsDuplicatePrefix = true
			records[i].DuplicateContainerName = dup.ContainerName
			if ops, ok := opsMap[dup.ContainerName]; ok {
				records[i].DuplicateContainerOps = ops
			}
		}
	}
}
