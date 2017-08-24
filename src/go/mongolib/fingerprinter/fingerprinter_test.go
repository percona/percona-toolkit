package fingerprinter

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"reflect"
	"testing"

	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
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

func ExampleFingerprint() {
	doc := proto.SystemProfile{}
	err := tutil.LoadBson(vars.RootPath+samples+"fingerprinter_doc.json", &doc)
	if err != nil {
		panic(err)
	}

	fp := NewFingerprinter(DEFAULT_KEY_FILTERS)
	got, err := fp.Fingerprint(doc)
	if err != nil {
		panic(err)
	}
	fmt.Println(got)
	// Output: FIND sbtest3 c,k,pad
}

func TestFingerprint(t *testing.T) {
	doc := proto.SystemProfile{}
	doc.Query = proto.BsonD{
		{"find", "feedback"},
		{"filter", bson.M{
			"tool":  "Atlas",
			"potId": "2c9180865ae33e85015af1cc29243dc5",
		}},
		{"limit", 1},
		{"singleBatch", true},
	}
	want := "FIND feedback potId,tool"

	fp := NewFingerprinter(nil)
	got, err := fp.Fingerprint(doc)

	if err != nil {
		t.Error("Error in fingerprint")
	}

	if got != want {
		t.Errorf("Invalid fingerprint. Got: %q, want %q", got, want)
	}
}

func TestFingerprints(t *testing.T) {
	t.Parallel()

	dir := vars.RootPath + samples + "/doc/out/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	expects := map[string]string{
		"aggregate_2.6.12":        "AGGREGATE coll a",
		"aggregate_3.0.15":        "AGGREGATE coll a",
		"aggregate_3.2.16":        "AGGREGATE coll a",
		"aggregate_3.4.7":         "AGGREGATE coll a",
		"aggregate_3.5.11":        "AGGREGATE coll a",
		"count_2.6.12":            "COUNT coll",
		"count_3.0.15":            "COUNT coll",
		"count_3.2.16":            "COUNT coll",
		"count_3.4.7":             "COUNT coll",
		"count_3.5.11":            "COUNT coll",
		"count_with_query_2.6.12": "COUNT coll a",
		"count_with_query_3.0.15": "COUNT coll a",
		"count_with_query_3.2.16": "COUNT coll a",
		"count_with_query_3.4.7":  "COUNT coll a",
		"count_with_query_3.5.11": "COUNT coll a",
		"delete_2.6.12":           "REMOVE coll a,b",
		"delete_3.0.15":           "REMOVE coll a,b",
		"delete_3.2.16":           "REMOVE coll a,b",
		"delete_3.4.7":            "REMOVE coll a,b",
		"delete_3.5.11":           "REMOVE coll a,b",
		"distinct_2.6.12":         "DISTINCT coll a,b",
		"distinct_3.0.15":         "DISTINCT coll a,b",
		"distinct_3.2.16":         "DISTINCT coll a,b",
		"distinct_3.4.7":          "DISTINCT coll a,b",
		"distinct_3.5.11":         "DISTINCT coll a,b",
		"find_empty_2.6.12":       "FIND coll",
		"find_empty_3.0.15":       "FIND coll",
		"find_empty_3.2.16":       "FIND coll",
		"find_empty_3.4.7":        "FIND coll",
		"find_empty_3.5.11":       "FIND coll",
		"find_2.6.12":             "FIND coll a",
		"find_3.0.15":             "FIND coll a",
		"find_3.2.16":             "FIND coll a",
		"find_3.4.7":              "FIND coll a",
		"find_3.5.11":             "FIND coll a",
		"find_andrii_2.6.12":      "FIND coll c,k,pad",
		"find_andrii_3.0.15":      "FIND coll c,k,pad",
		"find_andrii_3.2.16":      "FIND coll c,k,pad",
		"find_andrii_3.4.7":       "FIND coll c,k,pad",
		"find_andrii_3.5.11":      "FIND coll c,k,pad",
		"findandmodify_2.6.12":    "FINDANDMODIFY coll a",
		"findandmodify_3.0.15":    "FINDANDMODIFY coll a",
		"findandmodify_3.2.16":    "FINDANDMODIFY coll a",
		"findandmodify_3.4.7":     "FINDANDMODIFY coll a",
		"findandmodify_3.5.11":    "FINDANDMODIFY coll a",
		"geonear_2.6.12":          "GEONEAR coll",
		"geonear_3.0.15":          "GEONEAR coll",
		"geonear_3.2.16":          "GEONEAR coll",
		"geonear_3.4.7":           "GEONEAR coll",
		"geonear_3.5.11":          "GEONEAR coll",
		"group_2.6.12":            "GROUP coll a,b",
		"group_3.0.15":            "GROUP coll a,b",
		"group_3.2.16":            "GROUP coll a,b",
		"group_3.4.7":             "GROUP coll a,b",
		"group_3.5.11":            "GROUP coll a,b",
		"insert_2.6.12":           "INSERT coll",
		"insert_3.0.15":           "INSERT coll",
		"insert_3.2.16":           "INSERT coll",
		"insert_3.4.7":            "INSERT coll",
		"insert_3.5.11":           "INSERT coll",
		"mapreduce_2.6.12":        "MAPREDUCE coll a",
		"mapreduce_3.0.15":        "MAPREDUCE coll a",
		"mapreduce_3.2.16":        "MAPREDUCE coll a",
		"mapreduce_3.4.7":         "MAPREDUCE coll a",
		"mapreduce_3.5.11":        "MAPREDUCE coll a",
		"update_2.6.12":           "UPDATE coll a",
		"update_3.0.15":           "UPDATE coll a",
		"update_3.2.16":           "UPDATE coll a",
		"update_3.4.7":            "UPDATE coll a",
		"update_3.5.11":           "UPDATE coll a",
	}

	for _, file := range files {
		t.Run(file.Name(), func(t *testing.T) {
			doc := proto.SystemProfile{}
			err = tutil.LoadBson(dir+file.Name(), &doc)
			if err != nil {
				t.Fatalf("cannot load sample %s: %s", dir+file.Name(), err)
			}
			fp := NewFingerprinter(DEFAULT_KEY_FILTERS)
			got, err := fp.Fingerprint(doc)
			if err != nil {
				t.Errorf("cannot create fingerprint: %s", err)
			}
			expect := expects[file.Name()]
			if !reflect.DeepEqual(got, expect) {
				t.Errorf("fp.Fingerprint(doc) = %s, want %s", got, expect)
			}
		})
	}
}
