package util

import (
	"reflect"
	"testing"

	mgo "gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"

	"github.com/golang/mock/gomock"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo/pmgomock"
)

// OK
func TestGetReplicasetMembers(t *testing.T) {
	t.Skip("needs fixed")
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dialer := pmgomock.NewMockDialer(ctrl)

	session := pmgomock.NewMockSessionManager(ctrl)

	mockrss := proto.ReplicaSetStatus{
		Date:    "",
		MyState: 1,
		Term:    0,
		HeartbeatIntervalMillis: 0,
		Members: []proto.Members{
			proto.Members{
				Optime:        nil,
				OptimeDate:    "",
				InfoMessage:   "",
				ID:            0,
				Name:          "localhost:17001",
				Health:        1,
				StateStr:      "PRIMARY",
				Uptime:        113287,
				ConfigVersion: 1,
				Self:          true,
				State:         1,
				ElectionTime:  6340960613392449537,
				ElectionDate:  "",
				Set:           ""},
			proto.Members{
				Optime:        nil,
				OptimeDate:    "",
				InfoMessage:   "",
				ID:            1,
				Name:          "localhost:17002",
				Health:        1,
				StateStr:      "SECONDARY",
				Uptime:        113031,
				ConfigVersion: 1,
				Self:          false,
				State:         2,
				ElectionTime:  0,
				ElectionDate:  "",
				Set:           ""},
			proto.Members{
				Optime:        nil,
				OptimeDate:    "",
				InfoMessage:   "",
				ID:            2,
				Name:          "localhost:17003",
				Health:        1,
				StateStr:      "SECONDARY",
				Uptime:        113031,
				ConfigVersion: 1,
				Self:          false,
				State:         2,
				ElectionTime:  0,
				ElectionDate:  "",
				Set:           ""}},
		Ok:  1,
		Set: "r1",
	}
	expect := []proto.Members{
		proto.Members{
			Optime:        nil,
			OptimeDate:    "",
			InfoMessage:   "",
			ID:            0,
			Name:          "localhost:17001",
			Health:        1,
			StateStr:      "PRIMARY",
			Uptime:        113287,
			ConfigVersion: 1,
			Self:          true,
			State:         1,
			ElectionTime:  6340960613392449537,
			ElectionDate:  "",
			Set:           "r1"},
		proto.Members{Optime: (*proto.Optime)(nil),
			OptimeDate:    "",
			InfoMessage:   "",
			ID:            1,
			Name:          "localhost:17002",
			Health:        1,
			StateStr:      "SECONDARY",
			Uptime:        113031,
			ConfigVersion: 1,
			Self:          false,
			State:         2,
			ElectionTime:  0,
			ElectionDate:  "",
			Set:           "r1"},
		proto.Members{Optime: (*proto.Optime)(nil),
			OptimeDate:    "",
			InfoMessage:   "",
			ID:            2,
			Name:          "localhost:17003",
			Health:        1,
			StateStr:      "SECONDARY",
			Uptime:        113031,
			ConfigVersion: 1,
			Self:          false,
			State:         2,
			ElectionTime:  0,
			ElectionDate:  "",
			Set:           "r1",
		}}

	database := pmgomock.NewMockDatabaseManager(ctrl)
	ss := proto.ServerStatus{}
	tutil.LoadJson("test/sample/serverstatus.json", &ss)

	dialer.EXPECT().DialWithInfo(gomock.Any()).Return(session, nil)
	session.EXPECT().Run(bson.M{"replSetGetStatus": 1}, gomock.Any()).SetArg(1, mockrss)

	dialer.EXPECT().DialWithInfo(gomock.Any()).Return(session, nil)
	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)
	session.EXPECT().Close()

	dialer.EXPECT().DialWithInfo(gomock.Any()).Return(session, nil)
	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)
	session.EXPECT().Close()

	dialer.EXPECT().DialWithInfo(gomock.Any()).Return(session, nil)
	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)
	session.EXPECT().Close()

	session.EXPECT().Close()

	di := &mgo.DialInfo{Addrs: []string{"localhost"}}
	rss, err := GetReplicasetMembers(dialer, di)
	if err != nil {
		t.Errorf("getReplicasetMembers: %v", err)
	}
	if !reflect.DeepEqual(rss, expect) {
		t.Errorf("getReplicasetMembers:\ngot %#v\nwant: %#v\n", rss, expect)
	}

}

//OK
func TestGetHostnames(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dialer := pmgomock.NewMockDialer(ctrl)
	session := pmgomock.NewMockSessionManager(ctrl)

	mockShardsInfo := proto.ShardsInfo{
		Shards: []proto.Shard{
			proto.Shard{
				ID:   "r1",
				Host: "r1/localhost:17001,localhost:17002,localhost:17003",
			},
			proto.Shard{
				ID:   "r2",
				Host: "r2/localhost:18001,localhost:18002,localhost:18003",
			},
		},
		OK: 1,
	}

	dialer.EXPECT().DialWithInfo(gomock.Any()).Return(session, nil)
	session.EXPECT().Run("getShardMap", gomock.Any()).SetArg(1, mockShardsInfo)
	session.EXPECT().Close()

	expect := []string{"localhost", "localhost:17001", "localhost:18001"}
	di := &mgo.DialInfo{Addrs: []string{"localhost"}}
	rss, err := GetHostnames(dialer, di)
	if err != nil {
		t.Errorf("getHostnames: %v", err)
	}
	if !reflect.DeepEqual(rss, expect) {
		t.Errorf("getHostnames: got %+v, expected: %+v\n", rss, expect)
	}
}

func addToCounters(ss proto.ServerStatus, increment int64) proto.ServerStatus {
	ss.Opcounters.Command += increment
	ss.Opcounters.Delete += increment
	ss.Opcounters.GetMore += increment
	ss.Opcounters.Insert += increment
	ss.Opcounters.Query += increment
	ss.Opcounters.Update += increment
	return ss
}
