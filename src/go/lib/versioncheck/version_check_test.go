// This program is copyright 2017-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

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

		advice := []Advice{
			{
				Hash:     m[0],
				ToolName: m[1],
				Advice:   "There is a new version",
			},
		}

		buf, _ := json.Marshal(advice)
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
