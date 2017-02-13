package versioncheck

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestCheckUpdates(t *testing.T) {

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := ioutil.ReadAll(r.Body)
		m := strings.Split(string(body), ";")

		advices := []Advice{
			Advice{
				Hash:     m[0],
				ToolName: m[1],
				Advice:   "There is a new version",
			},
		}

		buf, _ := json.Marshal(advices)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, string(buf))
	}))
	defer ts.Close()
	os.Setenv("PERCONA_VERSION_CHECK_URL", ts.URL)

	msg, err := CheckUpdates("pt-test", "2.2.18")
	if err != nil {
		t.Errorf("error while checking %s", err)
	}
	if msg == "" {
		t.Error("got empty response")
	}

}

func TestEmptyResponse(t *testing.T) {

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "")
	}))
	defer ts.Close()
	os.Setenv("PERCONA_VERSION_CHECK_URL", ts.URL)

	msg, err := CheckUpdates("pt-test", "2.2.18")
	if err == nil {
		t.Error("response should return error due to empty body")
	}
	if msg != "" {
		t.Error("response should return error due to empty body")
	}

}
