package main

import (
	"io/ioutil"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/google/go-cmp/cmp"
)

var toolExecutable = "../../../bin/" + toolname

func TestMain(t *testing.T) {
	tests := []struct {
		name string
		cmd  []string
		path string
	}{
		{
			name: "upgrade_list_all",
			cmd:  []string{"list", "--all"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_sst",
			cmd:  []string{"list", "--sst"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_events",
			cmd:  []string{"list", "--events"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_views",
			cmd:  []string{"list", "--views"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_states",
			cmd:  []string{"list", "--states"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_all_since_until",
			cmd:  []string{"list", "--all", "--since=2023-03-12T13:13:14.886853Z", "--until=2023-03-12T19:35:07.644570Z"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_all_since",
			cmd:  []string{"list", "--all", "--since=2023-03-12T13:13:14.886853Z"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_all_until",
			cmd:  []string{"list", "--all", "--until=2023-03-12T19:35:07.644570Z"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_all_until_hiding_1_node",
			cmd:  []string{"list", "--all", "--until=2023-03-12T13:13:19.031367Z"},
			path: "tests/logs/upgrade/*.log",
		},
		{
			name: "upgrade_list_all_until_hiding_2_nodes",
			cmd:  []string{"list", "--all", "--until=2023-03-12T12:29:51.445280Z"},
			path: "tests/logs/upgrade/*.log",
		},
	}

	for _, test := range tests {
		filepaths, err := filepath.Glob(test.path)
		if err != nil {
			t.Fatalf("error during filepath.Glob(%s): %v", test.path, err)
		}
		test.cmd = append(test.cmd, filepaths...)
		out, err := exec.Command(toolExecutable, test.cmd...).CombinedOutput()
		if err != nil {
			t.Fatalf("error executing %s %s: %s: %s", toolExecutable, strings.Join(test.cmd, " "), err.Error(), string(out))
		}
		expected, err := ioutil.ReadFile("tests/expected/" + test.name)
		if err != nil {
			t.Fatalf("error loading test 'expected' file: %s", err)
		}

		if !cmp.Equal(out, expected) {
			t.Errorf("%s: test %s failed: %s\nout: %s", toolname, test.name, strings.Join(test.cmd, " "), cmp.Diff(string(out), string(expected)))
		}
	}

}

func TestVersionOption(t *testing.T) {
	out, err := exec.Command(toolExecutable, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(toolname + `\n.*Version v?\d+\.\d+\.\d+\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", toolname, out)
	}
}
