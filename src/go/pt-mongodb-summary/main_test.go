package main

import (
	"fmt"
	"reflect"
	"testing"
	"time"

	mgo "gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"

	"github.com/golang/mock/gomock"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo/pmgomock"
	"github.com/percona/toolkit-go-old/pt-mongodb-summary/test"
)

func TestGetOpCounterStats(t *testing.T) {

	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	session := pmgomock.NewMockSessionManager(ctrl)
	database := pmgomock.NewMockDatabaseManager(ctrl)

	ss := proto.ServerStatus{}
	test.LoadJson("test/sample/serverstatus.json", &ss)

	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)

	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)

	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)

	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)

	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)

	ss = addToCounters(ss, 1)
	session.EXPECT().DB("admin").Return(database)
	database.EXPECT().Run(bson.D{{"serverStatus", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, ss)

	var sampleCount int64 = 5
	var sampleRate time.Duration = 10 * time.Millisecond // in seconds
	expect := TimedStats{Min: 0, Max: 0, Total: 0, Avg: 0}

	os, err := GetOpCountersStats(session, sampleCount, sampleRate)
	if err != nil {
		t.Error(err)
	}
	if !reflect.DeepEqual(expect, os.Command) {
		t.Errorf("getOpCountersStats. got: %+v\nexpect: %+v\n", os.Command, expect)
	}

}

func TestSecurityOpts(t *testing.T) {
	cmdopts := []proto.CommandLineOptions{
		// 1
		proto.CommandLineOptions{
			Parsed: proto.Parsed{
				Net: proto.Net{
					SSL: proto.SSL{
						Mode: "",
					},
				},
			},
			Security: proto.Security{
				KeyFile:       "",
				Authorization: "",
			},
		},
		// 2
		proto.CommandLineOptions{
			Parsed: proto.Parsed{
				Net: proto.Net{
					SSL: proto.SSL{
						Mode: "",
					},
				},
			},
			Security: proto.Security{
				KeyFile:       "a file",
				Authorization: "",
			},
		},
		// 3
		proto.CommandLineOptions{
			Parsed: proto.Parsed{
				Net: proto.Net{
					SSL: proto.SSL{
						Mode: "",
					},
				},
			},
			Security: proto.Security{
				KeyFile:       "",
				Authorization: "something here",
			},
		},
		// 4
		proto.CommandLineOptions{
			Parsed: proto.Parsed{
				Net: proto.Net{
					SSL: proto.SSL{
						Mode: "super secure",
					},
				},
			},
			Security: proto.Security{
				KeyFile:       "",
				Authorization: "",
			},
		},
		// 5
		proto.CommandLineOptions{
			Parsed: proto.Parsed{
				Net: proto.Net{
					SSL: proto.SSL{
						Mode: "",
					},
				},
				Security: proto.Security{
					KeyFile: "/home/plavi/psmdb/percona-server-mongodb-3.4.0-1.0-beta-6320ac4/data/keyfile",
				},
			},
			Security: proto.Security{
				KeyFile:       "",
				Authorization: "",
			},
		},
	}

	expect := []*security{
		// 1
		&security{
			Users:       1,
			Roles:       2,
			Auth:        "disabled",
			SSL:         "disabled",
			BindIP:      "",
			Port:        0,
			WarningMsgs: nil,
		},
		// 2
		&security{
			Users:  1,
			Roles:  2,
			Auth:   "enabled",
			SSL:    "disabled",
			BindIP: "", Port: 0,
			WarningMsgs: nil,
		},
		// 3
		&security{
			Users:       1,
			Roles:       2,
			Auth:        "enabled",
			SSL:         "disabled",
			BindIP:      "",
			Port:        0,
			WarningMsgs: nil,
		},
		// 4
		&security{
			Users:       1,
			Roles:       2,
			Auth:        "disabled",
			SSL:         "super secure",
			BindIP:      "",
			Port:        0,
			WarningMsgs: nil,
		},
		// 5
		&security{
			Users:       1,
			Roles:       2,
			Auth:        "enabled",
			SSL:         "disabled",
			BindIP:      "",
			Port:        0,
			WarningMsgs: nil,
		},
	}

	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	session := pmgomock.NewMockSessionManager(ctrl)
	database := pmgomock.NewMockDatabaseManager(ctrl)

	usersCol := pmgomock.NewMockCollectionManager(ctrl)
	rolesCol := pmgomock.NewMockCollectionManager(ctrl)

	for i, cmd := range cmdopts {
		session.EXPECT().DB("admin").Return(database)
		database.EXPECT().Run(bson.D{{"getCmdLineOpts", 1}, {"recordStats", 1}}, gomock.Any()).SetArg(1, cmd)

		session.EXPECT().DB("admin").Return(database)
		database.EXPECT().C("system.users").Return(usersCol)
		usersCol.EXPECT().Count().Return(1, nil)

		session.EXPECT().DB("admin").Return(database)
		database.EXPECT().C("system.roles").Return(rolesCol)
		rolesCol.EXPECT().Count().Return(2, nil)

		got, err := GetSecuritySettings(session, "3.2")

		if err != nil {
			t.Errorf("cannot get sec settings: %v", err)
		}
		if !reflect.DeepEqual(got, expect[i]) {
			t.Errorf("Test # %d,\ngot: %#v\nwant: %#v\n", i+1, got, expect[i])
		}
	}
}

func TestGetNodeType(t *testing.T) {
	md := []struct {
		in  proto.MasterDoc
		out string
	}{
		{proto.MasterDoc{SetName: "name"}, "replset"},
		{proto.MasterDoc{Msg: "isdbgrid"}, "mongos"},
		{proto.MasterDoc{Msg: "a msg"}, "mongod"},
	}

	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	session := pmgomock.NewMockSessionManager(ctrl)
	for _, m := range md {
		session.EXPECT().Run("isMaster", gomock.Any()).SetArg(1, m.in)
		nodeType, err := getNodeType(session)
		if err != nil {
			t.Errorf("cannot get node type: %+v, error: %s\n", m.in, err)
		}
		if nodeType != m.out {
			t.Errorf("invalid node type. got %s, expect: %s\n", nodeType, m.out)
		}
	}
	session.EXPECT().Run("isMaster", gomock.Any()).Return(fmt.Errorf("some fake error"))
	nodeType, err := getNodeType(session)
	if err == nil {
		t.Errorf("error expected, got nil")
	}
	if nodeType != "" {
		t.Errorf("expected blank node type, got %s", nodeType)
	}

}

func TestGetReplicasetMembers(t *testing.T) {
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
				Id:            0,
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
				Id:            1,
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
				Id:            2,
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
			Id:            0,
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
			Id:            1,
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
			Id:            2,
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
	test.LoadJson("test/sample/serverstatus.json", &ss)

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
	rss, err := GetReplicasetMembers(dialer, []string{"localhost"}, di)
	if err != nil {
		t.Errorf("getReplicasetMembers: %v", err)
	}
	if !reflect.DeepEqual(rss, expect) {
		t.Errorf("getReplicasetMembers:\ngot %#v\nwant: %#v\n", rss, expect)
	}

}

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
	session.EXPECT().Run("listShards", gomock.Any()).SetArg(1, mockShardsInfo)
	session.EXPECT().Close()

	expect := []string{"localhost", "localhost:17001", "localhost:18001"}
	di := &mgo.DialInfo{Addrs: []string{"localhost"}}
	rss, err := getHostnames(dialer, di)
	if err != nil {
		t.Errorf("getHostnames: %v", err)
	}
	if !reflect.DeepEqual(rss, expect) {
		t.Errorf("getHostnames: got %+v, expected: %+v\n", rss, expect)
	}
}

func TestIsPrivateNetwork(t *testing.T) {
	//privateCIDRs := []string{"10.0.0.0/24", "172.16.0.0/20", "192.168.0.0/16"}
	testdata :=
		[]struct {
			ip   string
			want bool
			err  error
		}{
			{
				ip:   "127.0.0.1",
				want: true,
				err:  nil,
			},
			{
				ip:   "10.0.0.1",
				want: true,
				err:  nil,
			},
			{
				ip:   "10.0.1.1",
				want: false,
				err:  nil,
			},
			{
				ip:   "172.16.1.2",
				want: true,
				err:  nil,
			},
			{
				ip:   "192.168.1.2",
				want: true,
				err:  nil,
			},
			{
				ip:   "8.8.8.8",
				want: false,
				err:  nil,
			},
		}

	for _, in := range testdata {
		got, err := isPrivateNetwork(in.ip)
		if err != in.err {
			t.Errorf("ip %s. got err: %s, want err: %v", in.ip, err, in.err)
		}
		if got != in.want {
			t.Errorf("ip %s. got:  %v, want : %v", in.ip, got, in.want)
		}
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
