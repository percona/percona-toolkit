package main

import (
	"bytes"
	"os"
	"os/exec"
	"path"
	"strings"
	"testing"

	"golang.org/x/exp/slices"
)

/*
This test requires:
- Running K8 Operator installation
- kubectl configuration files, one for each supported operator
-- KUBECONFIG_PXC for K8SPXC
-- KUBECONFIG_PS for K8SPS
-- KUBECONFIG_PSMDB for K8SPSMDB
-- KUBECONFIG_PG for K8SPG

You can additionally set option FORWARDPORT if you want to use custom port when testing summaries.

pt-mysql-summary and pt-mongodb-summary must be in the PATH.

Since running pt-k8s-debug-collector may take long time run go test with increase timeout:
go test -timeout 6000s

We do not explicitly test --kubeconfig and --forwardport options, because they are used in other tests.
*/

/*
Tests collection of the individual files by pt-k8s-debug-collector.
Requires running K8SPXC instance and kubectl, configured to access that instance by default.
*/
func TestIndividualFiles(t *testing.T) {
	if os.Getenv("KUBECONFIG_PXC") == "" {
		t.Skip("TestIndividualFiles requires K8SPXC")
	}
	tests := []struct {
		name        string
		cmd         []string
		want        []string
		preprocesor func(string) string
	}{
		{
			// If the tool collects required log files
			name: "pxc_logs_list",
			// tar -tf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/*'
			cmd:  []string{"tar", "-tf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/*"},
			want: []string{"auto.cnf", "grastate.dat", "gvwstate.dat", "innobackup.backup.log", "innobackup.move.log", "innobackup.prepare.log", "mysqld-error.log", "mysqld.post.processing.log"},
			preprocesor: func(in string) string {
				files := strings.Split(in, "\n")
				var result []string
				for _, f := range files {
					b := path.Base(f)
					if !slices.Contains(result, b) && b != "." && b != "" {
						result = append(result, b)
					}
				}
				slices.Sort(result)
				return strings.Join(result, "\n")
			},
		},
		{
			// If MySQL error log is not empty
			name: "pxc_mysqld_error_log",
			// tar --to-command="grep -m 1 -o Version:" -xzf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/mysqld-error.log'
			cmd:  []string{"tar", "--to-command", "grep -m 1 -o Version:", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/mysqld-error.log"},
			want: []string{"Version:"},
			preprocesor: func(in string) string {
				nl := strings.Index(in, "\n")
				if nl == -1 {
					return ""
				}
				return in[:nl]
			},
		},
	}

	cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", os.Getenv("KUBECONFIG_PXC"), "--forwardport", os.Getenv("FORWARDPORT"), "--resource", "pxc")
	if err := cmd.Run(); err != nil {
		t.Errorf("error executing pt-k8s-debug-collector: %s", err.Error())
	}
	defer func() {
		cmd = exec.Command("rm", "-f", "cluster-dump.tar.gz")
		if err := cmd.Run(); err != nil {
			t.Errorf("error cleaning up test data: %s", err.Error())
		}
	}()

	for _, test := range tests {
		out, err := exec.Command(test.cmd[0], test.cmd[1:]...).CombinedOutput()
		if err != nil {
			t.Errorf("test %s, error running command %s:\n%s\n\nCommand output:\n%s", test.name, test.cmd[0], err.Error(), out)
		}
		if test.preprocesor(bytes.NewBuffer(out).String()) != strings.Join(test.want, "\n") {
			t.Errorf("test %s, output is not as expected\nOutput: %s\nWanted: %s", test.name, test.preprocesor(bytes.NewBuffer(out).String()), test.want)
		}
	}
}

/*
Tests for supported values of the --resource option
*/
func TestResourceOption(t *testing.T) {
	testcmd := []string{"sh", "-c", "tar -tf cluster-dump.tar.gz --wildcards '*/summary.txt' 2>/dev/null | wc -l"}
	tests := []struct {
		name       string
		want       string
		kubeconfig string
	}{
		{
			name:       "none",
			want:       "0",
			kubeconfig: "",
		},
		{
			name:       "pxc",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PXC"),
		},
		{
			name:       "ps",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PS"),
		},
		{
			name:       "psmdb",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PSMDB"),
		},
		{
			name:       "pg",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PG"),
		},
	}

	for _, test := range tests {
		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", test.kubeconfig, "--forwardport", os.Getenv("FORWARDPORT"), "--resource", test.name)
		if err := cmd.Run(); err != nil {
			t.Errorf("error executing pt-k8s-debug-collector: %s", err.Error())
		}
		defer func() {
			cmd = exec.Command("rm", "-f", "cluster-dump.tar.gz")
			if err := cmd.Run(); err != nil {
				t.Errorf("error cleaning up test data: %s", err.Error())
			}
		}()
		out, err := exec.Command(testcmd[0], testcmd[1:]...).Output()
		if err != nil {
			t.Errorf("test %s, error running command %s:\n%s\n\nCommand output:\n%s", test.name, testcmd, err.Error(), out)
		}
		if strings.TrimRight(bytes.NewBuffer(out).String(), "\n") != test.want {
			t.Errorf("test %s, output is not as expected\nOutput: %s\nWanted: %s", test.name, out, test.want)
		}
	}
}
