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
			name: "upgrade_list_all_no_color",
			cmd:  []string{"list", "--all", "--no-color"},
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

		{
			name: "merge_rotated_daily_list_all",
			cmd:  []string{"list", "--all"},
			path: "tests/logs/merge_rotated_daily/*",
		},
		{
			name: "merge_rotated_daily_list_all_since_keeping_latest_logs",
			cmd:  []string{"list", "--all", "--since=2023-03-18T21:18:23.102709+02:00"},
			path: "tests/logs/merge_rotated_daily/*",
		},

		{
			name: "operator_concurrent_ssts_list_all_no_color",
			cmd:  []string{"list", "--all", "--pxc-operator", "--no-color"},
			path: "tests/logs/operator_concurrent_ssts/*",
		},

		{
			name: "operator_ambiguous_ips_list_all_no_color",
			cmd:  []string{"list", "--all", "--pxc-operator", "--no-color"},
			path: "tests/logs/operator_ambiguous_ips/*",
		},

		{
			name: "operator_split_list_all_no_color",
			cmd:  []string{"list", "--all", "--pxc-operator", "--no-color"},
			path: "tests/logs/operator_split/*",
		},

		{
			name: "conflict_conflicts",
			cmd:  []string{"conflicts"},
			path: "tests/logs/conflict/*",
		},
	}

TESTS:
	for _, test := range tests {
		filepaths, err := filepath.Glob(test.path)
		if err != nil {
			t.Fatalf("error during filepath.Glob(%s): %v", test.path, err)
		}
		test.cmd = append(test.cmd, filepaths...)

		// because there has been some cases that created few different outputs
		// source of random: order of files read, map iteration order are random and it affects map merges
		for i := 0; i < 5; i++ {
			out, err := exec.Command(toolExecutable, test.cmd...).CombinedOutput()
			if err != nil {
				t.Fatalf("error executing %s %s: %s: %s", toolExecutable, strings.Join(test.cmd, " "), err.Error(), string(out))
			}
			expected, err := ioutil.ReadFile("tests/expected/" + test.name)
			if err != nil {
				t.Fatalf("error loading test 'expected' file: %s", err)
			}

			if !cmp.Equal(out, expected) {
				t.Errorf("%s: test %s failed: %s\nout: %s", toolname, test.name, strings.Join(test.cmd, " "), cmp.Diff(string(expected), string(out)))
				continue TESTS
			}
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
