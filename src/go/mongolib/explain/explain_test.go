package explain

import (
	"io/ioutil"
	"log"
	"os"
	"testing"

	"fmt"

	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/percona/pmgo"
	"github.com/stretchr/testify/require"
	"gopkg.in/mgo.v2/bson"
)

const (
	samples = "/src/go/tests/"
)

type testVars struct {
	RootPath string
}

var vars testVars

func TestMain(m *testing.M) {
	var err error
	if vars.RootPath, err = tutil.RootPath(); err != nil {
		log.Printf("cannot get root path: %s", err.Error())
		os.Exit(1)
	}
	os.Exit(m.Run())
}

func TestExplain(t *testing.T) {
	t.Parallel()

	dir := vars.RootPath + samples + "/doc/out/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	expectError := map[string]string{
		"aggregate_2.6.12":        "Cannot explain cmd: aggregate",
		"aggregate_3.0.15":        "Cannot explain cmd: aggregate",
		"aggregate_3.2.16":        "Cannot explain cmd: aggregate",
		"aggregate_3.4.7":         "Cannot explain cmd: aggregate",
		"aggregate_3.5.11":        "Cannot explain cmd: aggregate",
		"count_2.6.12":            "<nil>",
		"count_3.0.15":            "<nil>",
		"count_3.2.16":            "<nil>",
		"count_3.4.7":             "<nil>",
		"count_3.5.11":            "<nil>",
		"count_with_query_2.6.12": "<nil>",
		"count_with_query_3.0.15": "<nil>",
		"count_with_query_3.2.16": "<nil>",
		"count_with_query_3.4.7":  "<nil>",
		"count_with_query_3.5.11": "<nil>",
		"delete_2.6.12":           "<nil>",
		"delete_3.0.15":           "<nil>",
		"delete_3.2.16":           "<nil>",
		"delete_3.4.7":            "<nil>",
		"delete_3.5.11":           "<nil>",
		"delete_all_2.6.12":       "<nil>",
		"delete_all_3.0.15":       "<nil>",
		"delete_all_3.2.16":       "<nil>",
		"delete_all_3.4.7":        "<nil>",
		"delete_all_3.5.11":       "<nil>",
		"distinct_2.6.12":         "<nil>",
		"distinct_3.0.15":         "<nil>",
		"distinct_3.2.16":         "<nil>",
		"distinct_3.4.7":          "<nil>",
		"distinct_3.5.11":         "<nil>",
		"find_empty_2.6.12":       "<nil>",
		"find_empty_3.0.15":       "<nil>",
		"find_empty_3.2.16":       "<nil>",
		"find_empty_3.4.7":        "<nil>",
		"find_empty_3.5.11":       "<nil>",
		"find_2.6.12":             "<nil>",
		"find_3.0.15":             "<nil>",
		"find_3.2.16":             "<nil>",
		"find_3.4.7":              "<nil>",
		"find_3.5.11":             "<nil>",
		"find_andrii_2.6.12":      "<nil>",
		"find_andrii_3.0.15":      "<nil>",
		"find_andrii_3.2.16":      "<nil>",
		"find_andrii_3.4.7":       "<nil>",
		"find_andrii_3.5.11":      "<nil>",
		"findandmodify_2.6.12":    "<nil>",
		"findandmodify_3.0.15":    "<nil>",
		"findandmodify_3.2.16":    "<nil>",
		"findandmodify_3.4.7":     "<nil>",
		"findandmodify_3.5.11":    "<nil>",
		"geonear_2.6.12":          "Cannot explain cmd: geoNear",
		"geonear_3.0.15":          "Cannot explain cmd: geoNear",
		"geonear_3.2.16":          "Cannot explain cmd: geoNear",
		"geonear_3.4.7":           "Cannot explain cmd: geoNear",
		"geonear_3.5.11":          "Cannot explain cmd: geoNear",
		"group_2.6.12":            "<nil>",
		"group_3.0.15":            "<nil>",
		"group_3.2.16":            "<nil>",
		"group_3.4.7":             "<nil>",
		"group_3.5.11":            "<nil>",
		"insert_2.6.12":           "Cannot explain cmd: insert",
		"insert_3.0.15":           "Cannot explain cmd: insert",
		"insert_3.2.16":           "Cannot explain cmd: insert",
		"insert_3.4.7":            "Cannot explain cmd: insert",
		"insert_3.5.11":           "Cannot explain cmd: insert",
		"mapreduce_2.6.12":        "Cannot explain cmd: mapReduce",
		"mapreduce_3.0.15":        "Cannot explain cmd: mapReduce",
		"mapreduce_3.2.16":        "Cannot explain cmd: mapReduce",
		"mapreduce_3.4.7":         "Cannot explain cmd: mapReduce",
		"mapreduce_3.5.11":        "Cannot explain cmd: mapReduce",
		"update_2.6.12":           "<nil>",
		"update_3.0.15":           "<nil>",
		"update_3.2.16":           "<nil>",
		"update_3.4.7":            "<nil>",
		"update_3.5.11":           "<nil>",
	}

	dialer := pmgo.NewDialer()
	dialInfo, err := pmgo.ParseURL("127.0.0.1:27017")
	require.NoError(t, err)

	session, err := dialer.DialWithInfo(dialInfo)
	require.NoError(t, err)
	defer session.Close()

	ex := New(session)

	for _, file := range files {
		t.Run(file.Name(), func(t *testing.T) {
			eq := proto.ExampleQuery{}
			err := tutil.LoadBson(dir+file.Name(), &eq)
			if err != nil {
				t.Fatalf("cannot load sample %s: %s", dir+file.Name(), err)
			}
			got, err := ex.Explain(eq)
			expectErrMsg := expectError[file.Name()]
			gotErrMsg := fmt.Sprintf("%v", err)
			if gotErrMsg != expectErrMsg {
				t.Fatalf("explain error should be '%s' but was '%s'", expectErrMsg, gotErrMsg)
			}

			if err != nil {
				return
			}

			result := proto.BsonD{}
			err = bson.UnmarshalJSON(got, &result)
			if err != nil {
				t.Fatalf("cannot unmarshal json explain result: %s", err)
			}
		})
	}
}
