// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
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

package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// toolExecutable is built once in TestMain so the suite is self-contained and
// does not depend on `make build` having run first.
var toolExecutable string

// expectedDir holds the golden output files, one per test case name.
const expectedDir = "tests/expected"

func TestMain(m *testing.M) {
	tmp, err := os.MkdirTemp("", "pt-mongo-log-explainer-test")
	if err != nil {
		panic("cannot create temp dir: " + err.Error())
	}
	defer os.RemoveAll(tmp)

	bin := filepath.Join(tmp, toolname)
	build := exec.Command("go", "build", "-o", bin, ".")
	build.Stderr = os.Stderr
	if err := build.Run(); err != nil {
		panic("cannot build " + toolname + " for tests: " + err.Error())
	}
	toolExecutable = bin

	os.Exit(m.Run())
}

// runTool executes the built binary with the given arguments, expanding the
// optional path glob, and returns stdout only (stderr carries log lines that
// must not pollute the golden output).
func runTool(t *testing.T, args []string, pathGlob string) []byte {
	t.Helper()

	full := append([]string{}, args...)
	if pathGlob != "" {
		matches, err := filepath.Glob(pathGlob)
		if err != nil {
			t.Fatalf("bad glob %q: %v", pathGlob, err)
		}
		if len(matches) == 0 {
			t.Fatalf("glob %q matched no files", pathGlob)
		}
		full = append(full, matches...)
	}

	cmd := exec.Command(toolExecutable, full...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("running %s %s failed: %v\nstderr: %s",
			toolExecutable, strings.Join(full, " "), err, stderr.String())
	}
	return stdout.Bytes()
}

// TestCommands runs each command against the fixture logs and compares stdout to
// a golden file. Set UPDATE_GOLDEN=1 to (re)generate the golden files.
//
// Each case is executed several times because map iteration and file read order
// are randomized in Go; this guards against accidental non-determinism.
func TestCommands(t *testing.T) {
	cases := []struct {
		name string
		args []string
		path string
	}{
		{"summary_replicaset", []string{"summary", "--no-color"}, "tests/logs/replicaset/*.log"},
		{"summary_sharded", []string{"summary", "--no-color"}, "tests/logs/sharded/*.log"},
		{"whois_ip", []string{"whois", "--no-color", "192.168.1.10"}, "tests/logs/replicaset/*.log"},
		{"whois_nodename", []string{"whois", "--no-color", "mongo-rs0-0"}, "tests/logs/replicaset/*.log"},
		{"whois_id", []string{"whois", "--no-color", "0"}, "tests/logs/replicaset/*.log"},
		{"timeline_all", []string{"timeline", "--no-color"}, "tests/logs/replicaset/*.log"},
		{"timeline_replication", []string{"timeline", "--replication", "--no-color"}, "tests/logs/replicaset/*.log"},
		{"timeline_elections", []string{"timeline", "--elections", "--no-color"}, "tests/logs/replicaset/*.log"},
		{"timeline_json", []string{"timeline", "--json"}, "tests/logs/replicaset/*.log"},
		{"timeline_sharding", []string{"timeline", "--sharding", "--no-color"}, "tests/logs/sharded/*.log"},
		{"list_all", []string{"list", "--all", "--no-color"}, "tests/logs/replicaset/*.log"},
		{"regex_list", []string{"regex-list"}, ""},

		// Real-world MongoDB 7.0 structured (JSON) log shape. Guards the version
		// parser against false positives (OS release, driver version, loopback IP).
		{"summary_standalone_70", []string{"summary", "--no-color"}, "tests/logs/standalone/*.log"},
		{"list_standalone_70", []string{"list", "--all", "--no-color"}, "tests/logs/standalone/*.log"},
	}

	update := os.Getenv("UPDATE_GOLDEN") != ""

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			goldenPath := filepath.Join(expectedDir, tc.name)

			var first []byte
			const runs = 5
			for i := 0; i < runs; i++ {
				out := runTool(t, tc.args, tc.path)
				if i == 0 {
					first = out
					continue
				}
				if !bytes.Equal(first, out) {
					t.Fatalf("non-deterministic output across runs for %q:\n--- run 0 ---\n%s\n--- run %d ---\n%s",
						tc.name, first, i, out)
				}
			}

			if update {
				if err := os.MkdirAll(expectedDir, 0o755); err != nil {
					t.Fatalf("cannot create %s: %v", expectedDir, err)
				}
				if err := os.WriteFile(goldenPath, first, 0o644); err != nil {
					t.Fatalf("cannot write golden %s: %v", goldenPath, err)
				}
				return
			}

			want, err := os.ReadFile(goldenPath)
			if err != nil {
				t.Fatalf("cannot read golden %s (run with UPDATE_GOLDEN=1 to create): %v", goldenPath, err)
			}
			if !bytes.Equal(want, first) {
				t.Errorf("output mismatch for %q\n%s", tc.name, firstDiff(want, first))
			}
		})
	}
}

// firstDiff returns a short human-readable description of the first line that
// differs between want and got.
func firstDiff(want, got []byte) string {
	wl := strings.Split(string(want), "\n")
	gl := strings.Split(string(got), "\n")
	n := len(wl)
	if len(gl) < n {
		n = len(gl)
	}
	for i := 0; i < n; i++ {
		if wl[i] != gl[i] {
			return "first difference at line " + itoa(i+1) +
				"\n  want: " + wl[i] +
				"\n  got:  " + gl[i]
		}
	}
	if len(wl) != len(gl) {
		return "outputs have different line counts: want " + itoa(len(wl)) + ", got " + itoa(len(gl))
	}
	return "(no line-level difference found)"
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b [20]byte
	p := len(b)
	for i > 0 {
		p--
		b[p] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		p--
		b[p] = '-'
	}
	return string(b[p:])
}

// TestVersionOption verifies that --version prints the tool name and a version
// line. The version value comes from the build (ldflags); when built without
// ldflags it falls back to an empty string, so we only require the labels.
func TestVersionOption(t *testing.T) {
	out, err := exec.Command(toolExecutable, "--version").Output()
	if err != nil {
		t.Fatalf("error executing %s --version: %v", toolname, err)
	}
	re := regexp.MustCompile(`(?s)` + regexp.QuoteMeta(toolname) + `.*Version.*Build:.*Commit:`)
	if !re.Match(out) {
		t.Errorf("%s --version produced unexpected output:\n%s", toolname, out)
	}
}
