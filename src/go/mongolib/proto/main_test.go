package proto_test

import (
	"fmt"
	"io/ioutil"
	"os"
	"testing"

	mgo "gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
	"gopkg.in/mgo.v2/dbtest"
)

var Server dbtest.DBServer
var session *mgo.Session

func TestMain(m *testing.M) {
	// The tempdir is created so MongoDB has a location to store its files.
	// Contents are wiped once the server stops
	os.Setenv("CHECK_SESSIONS", "0")
	tempDir, _ := ioutil.TempDir("", "testing")
	Server.SetPath(tempDir)
	session = Server.Session()

	retCode := m.Run()

	Server.Session().Close()
	Server.Wipe()

	// Stop shuts down the temporary server and removes data on disk.
	Server.Stop()

	// call with result of m.Run()
	os.Exit(retCode)
}

func ExamplePing() {
	ss := map[string]interface{}{}
	if err := session.DB("admin").Run(bson.D{{"ping", 1}}, &ss); err != nil {
		panic(err)
	}
	fmt.Printf("%+v", ss)
	// Output: map[ok:1]
}
