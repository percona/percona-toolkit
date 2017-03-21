package oplog

import (
	"fmt"
	"sort"
	"time"

	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"
	"github.com/pkg/errors"
	"gopkg.in/mgo.v2/bson"
)

func GetOplogInfo(hostnames []string, di *pmgo.DialInfo) ([]proto.OplogInfo, error) {

	results := proto.OpLogs{}

	for _, hostname := range hostnames {
		result := proto.OplogInfo{
			Hostname: hostname,
		}
		di.Addrs = []string{hostname}
		dialer := pmgo.NewDialer()
		session, err := dialer.DialWithInfo(di)
		if err != nil {
			continue
		}
		defer session.Close()

		oplogCol, err := getOplogCollection(session)
		if err != nil {
			continue
		}

		olEntry, err := getOplogEntry(session, oplogCol)
		if err != nil {
			return nil, errors.Wrap(err, "getOplogInfo -> GetOplogEntry")
		}
		result.Size = olEntry.Options.Size / (1024 * 1024)

		var colStats proto.OplogColStats
		err = session.DB("local").Run(bson.M{"collStats": oplogCol}, &colStats)
		if err != nil {
			return nil, errors.Wrapf(err, "cannot get collStats for collection %s", oplogCol)
		}

		result.UsedMB = colStats.Size / (1024 * 1024)

		var firstRow, lastRow proto.OplogRow
		err = session.DB("local").C(oplogCol).Find(nil).Sort("$natural").One(&firstRow)
		if err != nil {
			return nil, errors.Wrap(err, "cannot read first oplog row")
		}

		err = session.DB("local").C(oplogCol).Find(nil).Sort("-$natural").One(&lastRow)
		if err != nil {
			return nil, errors.Wrap(err, "cannot read last oplog row")
		}

		// https://docs.mongodb.com/manual/reference/bson-types/#timestamps
		tfirst := firstRow.Ts >> 32
		tlast := lastRow.Ts >> 32
		result.TimeDiff = tlast - tfirst
		result.TimeDiffHours = float64(result.TimeDiff) / 3600

		result.TFirst = time.Unix(tfirst, 0)
		result.TLast = time.Unix(tlast, 0)
		result.Now = time.Now().UTC()
		if result.TimeDiffHours > 24 {
			result.Running = fmt.Sprintf("%0.2f days", result.TimeDiffHours/24)
		} else {
			result.Running = fmt.Sprintf("%0.2f hours", result.TimeDiffHours)
		}

		replSetStatus := proto.ReplicaSetStatus{}
		err = session.Run(bson.M{"replSetGetStatus": 1}, &replSetStatus)
		if err != nil {
			continue
		}

		for _, member := range replSetStatus.Members {
			if member.State == 1 {
				result.ElectionTime = time.Unix(member.ElectionTime>>32, 0)
				break
			}
		}
		results = append(results, result)
	}

	sort.Sort(results)
	return results, nil

}

func getOplogCollection(session pmgo.SessionManager) (string, error) {
	oplog := "oplog.rs"

	db := session.DB("local")
	nsCol := db.C("system.namespaces")

	var res interface{}
	if err := nsCol.Find(bson.M{"name": "local." + oplog}).One(&res); err == nil {
		return oplog, nil
	}

	oplog = "oplog.$main"
	if err := nsCol.Find(bson.M{"name": "local." + oplog}).One(&res); err != nil {
		return "", fmt.Errorf("neither master/slave nor replica set replication detected")
	}

	return oplog, nil
}

func getOplogEntry(session pmgo.SessionManager, oplogCol string) (*proto.OplogEntry, error) {
	olEntry := &proto.OplogEntry{}

	err := session.DB("local").C("system.namespaces").Find(bson.M{"name": "local." + oplogCol}).One(&olEntry)
	if err != nil {
		return nil, fmt.Errorf("local.%s, or its options, not found in system.namespaces collection", oplogCol)
	}
	return olEntry, nil
}
