package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"reflect"
	"testing"
	"time"

	"gopkg.in/mgo.v2/bson"
	"gopkg.in/mgo.v2/dbtest"

	"github.com/golang/mock/gomock"
	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"
	"github.com/percona/pmgo/pmgomock"
)

func TestGetOpCounterStats(t *testing.T) {

	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	session := pmgomock.NewMockSessionManager(ctrl)
	database := pmgomock.NewMockDatabaseManager(ctrl)

	ss := proto.ServerStatus{}
	tutil.LoadJson("test/sample/serverstatus.json", &ss)

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

	var sampleCount int = 5
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

func TestGetChunks(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	session := pmgomock.NewMockSessionManager(ctrl)
	database := pmgomock.NewMockDatabaseManager(ctrl)
	pipe := pmgomock.NewMockPipeManager(ctrl)
	col := pmgomock.NewMockCollectionManager(ctrl)

	var res []proto.ChunksByCollection
	tutil.LoadJson("test/sample/chunks.json", &res)

	pipe.EXPECT().All(gomock.Any()).SetArg(0, res)

	col.EXPECT().Pipe(gomock.Any()).Return(pipe)

	database.EXPECT().C("chunks").Return(col)

	session.EXPECT().DB("config").Return(database)

	want := []proto.ChunksByCollection{
		{ID: "samples.col2", Count: 5},
	}

	got, err := getChunksCount(session)
	if err != nil {
		t.Errorf("Cannot get chunks: %s", err.Error())
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Invalid getChunksCount response.\ngot: %+v\nwant: %+v\n", got, want)
	}
}

func TestIntegrationGetChunks(t *testing.T) {
	var server dbtest.DBServer
	os.Setenv("CHECK_SESSIONS", "0")
	tempDir, _ := ioutil.TempDir("", "testing")
	server.SetPath(tempDir)

	session := pmgo.NewSessionManager(server.Session())
	session.DB("config").C("chunks").Insert(bson.M{"ns": "samples.col1", "count": 2})

	want := []proto.ChunksByCollection{
		proto.ChunksByCollection{
			ID:    "samples.col1",
			Count: 1,
		},
	}
	got, err := getChunksCount(session)
	if err != nil {
		t.Errorf("Error in integration chunks count: %s", err.Error())
	}

	if !reflect.DeepEqual(got, want) {
		t.Errorf("Invalid integration chunks count.\ngot: %+v\nwant: %+v", got, want)
	}

	server.Session().DB("config").DropDatabase()
	server.Session().Close()
	server.Stop()

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
