package oplog

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/percona-toolkit/src/go/mongolib/util"
	"github.com/pkg/errors"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func GetOplogInfo(ctx context.Context, hostnames []string, co *options.ClientOptions) ([]proto.OplogInfo, error) {
	results := proto.OpLogs{}

	for _, hostname := range hostnames {
		result := proto.OplogInfo{
			Hostname: hostname,
		}
		client, err := util.GetClientForHost(co, hostname)
		if err != nil {
			return nil, errors.Wrap(err, "cannot get a client (GetOplogInfo)")
		}
		if err := client.Connect(ctx); err != nil {
			return nil, errors.Wrapf(err, "cannot connect to %s", hostname)
		}

		oplogCol, err := getOplogCollection(ctx, client)
		if err != nil {
			return nil, errors.Wrap(err, "cannot determine the oplog collection")
		}

		var colStats proto.OplogColStats
		err = client.Database("local").RunCommand(ctx, bson.M{"collStats": oplogCol}).Decode(&colStats)
		if err != nil {
			return nil, errors.Wrapf(err, "cannot get collStats for collection %s", oplogCol)
		}

		result.Size = colStats.Size
		result.UsedMB = colStats.Size / (1024 * 1024)

		var firstRow, lastRow proto.OplogRow
		options := options.FindOne()
		options.SetSort(bson.M{"$natural": 1})
		err = client.Database("local").Collection(oplogCol).FindOne(ctx, bson.M{}, options).Decode(&firstRow)
		if err != nil {
			return nil, errors.Wrap(err, "cannot read first oplog row")
		}

		options.SetSort(bson.M{"$natural": -1})
		err = client.Database("local").Collection(oplogCol).FindOne(ctx, bson.M{}, options).Decode(&lastRow)
		if err != nil {
			return nil, errors.Wrap(err, "cannot read last oplog row")
		}

		result.TFirst = time.Unix(int64(firstRow.Timestamp.T), int64(firstRow.Timestamp.I))
		result.TLast = time.Unix(int64(lastRow.Timestamp.T), int64(lastRow.Timestamp.I))
		result.TimeDiff = result.TLast.Sub(result.TFirst)
		result.TimeDiffHours = result.TimeDiff.Hours()
		result.Now = time.Now().UTC()
		if result.TimeDiffHours > 24 {
			result.Running = fmt.Sprintf("%0.2f days", result.TimeDiffHours/24)
		} else {
			result.Running = fmt.Sprintf("%0.2f hours", result.TimeDiffHours)
		}

		replSetStatus := proto.ReplicaSetStatus{}
		err = client.Database("admin").RunCommand(ctx, bson.M{"replSetGetStatus": 1}).Decode(&replSetStatus)
		if err != nil {
			continue
		}

		for _, member := range replSetStatus.Members {
			if member.State == 1 {
				result.ElectionTime = time.Unix(int64(member.ElectionTime.T), 0)
				break
			}
		}
		results = append(results, result)
	}

	sort.Sort(results)
	return results, nil
}

func getOplogCollection(ctx context.Context, client *mongo.Client) (string, error) {
	oplog := "oplog.rs"

	filter := bson.M{"name": bson.M{"$eq": oplog}}
	cursor, err := client.Database("local").ListCollections(ctx, filter)
	if err != nil {
		return "", errors.Wrap(err, "cannot getOplogCollection")
	}

	defer cursor.Close(ctx)
	for cursor.Next(ctx) {
		n := bson.M{}
		if err := cursor.Decode(&n); err != nil {
			continue
		}
		return oplog, nil
	}

	return "", fmt.Errorf("cannot find the oplog collection")
}

func getOplogEntry(ctx context.Context, client *mongo.Client, oplogCol string) (*proto.OplogEntry, error) {
	olEntry := &proto.OplogEntry{}

	err := client.Database("local").Collection("system.namespaces").
		FindOne(ctx, bson.M{"name": "local." + oplogCol}).Decode(&olEntry)
	if err != nil {
		return nil, fmt.Errorf("local.%s, or its options, not found in system.namespaces collection", oplogCol)
	}
	return olEntry, nil
}
