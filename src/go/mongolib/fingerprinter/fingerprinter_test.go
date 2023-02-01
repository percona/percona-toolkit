package fingerprinter

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/percona/percona-toolkit/src/go/lib/tutil"
	"github.com/percona/percona-toolkit/src/go/mongolib/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/bson"
)

const (
	samples = "/testdata/"
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

func TestSingleFingerprint(t *testing.T) {
	doc := proto.SystemProfile{}
	doc.Ns = "db.feedback"
	doc.Op = "query"
	doc.Query = bson.D{
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

	dir := filepath.Join(vars.RootPath, "/src/go/tests/doc/profiles")
	dirExpect := filepath.Join(vars.RootPath, "/src/go/tests/expect/fingerprints/")
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		t.Fatalf("cannot list samples: %s", err)
	}

	for _, file := range files {
		t.Run(file.Name(), func(t *testing.T) {
			doc := proto.SystemProfile{}
			err = tutil.LoadBson(filepath.Join(dir, file.Name()), &doc)
			assert.NoError(t, err)

			fp := NewFingerprinter(DefaultKeyFilters())
			got, err := fp.Fingerprint(doc)
			require.NoError(t, err)
			if err != nil {
				t.Errorf("cannot create fingerprint: %s", err)
			}

			fExpect := filepath.Join(dirExpect, file.Name())
			fExpect = strings.TrimSuffix(fExpect, ".bson")

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
