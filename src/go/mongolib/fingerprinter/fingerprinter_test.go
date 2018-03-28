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
	fmt.Println(got.Fingerprint)
	// Output: FIND sbtest3 c,k,pad
}

func TestFingerprint(t *testing.T) {
	doc := proto.SystemProfile{}
	doc.Ns = "db.feedback"
	doc.Op = "query"
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

	if got.Fingerprint != want {
		t.Errorf("Invalid fingerprint. Got: %q, want %q", got.Fingerprint, want)
	}
}

func TestFingerprints(t *testing.T) {
	t.Parallel()

	dir := vars.RootPath + samples + "/doc/out/"
	dirExpect := vars.RootPath + samples + "/expect/fingerprints/"
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
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
			fExpect := dirExpect + file.Name()
			if tutil.ShouldUpdateSamples() {
				err := tutil.WriteJson(fExpect, got)
				if err != nil {
					fmt.Printf("cannot update samples: %s", err.Error())
				}
			}
			var expect Fingerprint
			err = tutil.LoadJson(fExpect, &expect)
			if err != nil {
				t.Fatalf("cannot load expected data %s: %s", fExpect, err)
			}

			if !reflect.DeepEqual(got, expect) {
				t.Errorf("fp.Fingerprint(doc) = %s, want %s", got, expect)
			}
		})
	}
}
