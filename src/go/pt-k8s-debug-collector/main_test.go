package main

import (
	"bytes"
	"os"
	"os/exec"
	"path"
	"regexp"
	"sort"
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
-- KUBECONFIG_PG2 for K8SPG version 2

You can additionally set option FORWARDPORT if you want to use custom port when testing summaries.

pt-mysql-summary, mysql, psql, and pt-mongodb-summary must be in the PATH.

Since running pt-k8s-debug-collector may take long time run go test with increase timeout:
go test -timeout 6000s

We do not explicitly test --kubeconfig and --forwardport options, because they are used in other tests.
*/

/*
Tests TODO:

- Test clusters with custom user and secrets. With the way we currently test,
  we just need to create a cluster with particular options. But it is already
  time and resource consuming operation. So we need to either test only getCR
  function or create a mock cluster, or find a better way to deploy test clusters.
*/

type Resource struct {
	name string
	env  string
}

var (
	PxcResource  = Resource{name: "pxc", env: "KUBECONFIG_PXC"}
	PgResource   = Resource{name: "pg", env: "KUBECONFIG_PG"}
	AutoResource = Resource{name: "auto", env: "KUBECONFIG_PXC"}
)

type Matcher interface {
	Match(t *testing.T, got string)
}

type ExactMatch struct {
	Want []string
}

func (m ExactMatch) Match(t *testing.T, got string) {
	want := strings.Join(m.Want, "\n")
	if got != want {
		t.Fatalf("output mismatch\nGot:\n%s\nWant:\n%s", got, want)
	}
}

type RegexMatch struct {
	Pattern *regexp.Regexp
}

func (m RegexMatch) Match(t *testing.T, got string) {
	for line := range strings.SplitSeq(got, "\n") {
		if m.Pattern.MatchString(line) {
			return
		}
	}
	t.Fatalf("no line matches pattern %s\nGot:\n%s", m.Pattern, got)
}

func uniqueBasenames(in string) string {
	files := strings.Split(in, "\n")
	var result []string
	for _, f := range files {
		b := path.Base(f)
		if !slices.Contains(result, b) && b != "." && b != "" {
			result = append(result, b)
		}
	}
	sort.Strings(result)
	return strings.Join(result, "\n")
}

func firstLine(in string) string {
	nl := strings.Index(in, "\n")
	if nl == -1 {
		return in
	}
	return in[:nl]
}

/*
   Tests collection of the individual files by pt-k8s-debug-collector.
   Requires running K8SPXC instance and kubectl, configured to access that instance by default.
   If some of the env (KUBECONFIG_PXC, KUBECONFIG_PG) is not defined, theese tests will be skiped.
*/

func TestIndividualFiles(t *testing.T) {
	tests := []struct {
		name         string
		cmd          []string
		env          string
		preprocessor func(string) string
		match        Matcher
	}{
		{
			// If the tool collects required mysql log files
			name: "pxc_logs_list",
			// tar -tf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/*'
			cmd:          []string{"tar", "-tf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/*"},
			env:          "KUBECONFIG_PXC",
			preprocessor: uniqueBasenames,
			match: ExactMatch{
				Want: []string{
					"auto.cnf",
					"grastate.dat",
					"gvwstate.dat",
					"innobackup.backup.log",
					"innobackup.move.log",
					"innobackup.prepare.log",
					"mysqld-error.log",
					"mysqld.post.processing.log",
				},
			},
		},
		{
			// If MySQL error log is not empty
			name: "pxc_mysqld_error_log",
			// tar --to-command="grep -m 1 -o Version:" -xzf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/mysqld-error.log'
			cmd:          []string{"tar", "--to-command", "grep -m 1 -o Version:", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/mysqld-error.log"},
			env:          "KUBECONFIG_PXC",
			preprocessor: firstLine,
			match: ExactMatch{
				Want: []string{"Version:"},
			},
		},
		{
			// if the tool collects required pg log files
			name:         "pg_logs_list",
			cmd:          []string{"tar", "-tf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*/pgdata/*"},
			env:          "KUBECONFIG_PG",
			preprocessor: uniqueBasenames,
			match: RegexMatch{
				Pattern: regexp.MustCompile(`^postgresql-[A-Za-z]{3}\.log$`),
			},
		},
	}

	for _, resource := range []Resource{PxcResource, PgResource, AutoResource} {
		if os.Getenv(resource.env) == "" {
			t.Logf("TestIndividualFiles requires %s env", resource.env)
			continue
		}

		cmd := exec.Command("../../../bin/pt-k8s-debug-collector",
			"--kubeconfig", os.Getenv(resource.env),
			"--forwardport", os.Getenv("FORWARDPORT"),
			"--resource", resource.name,
		)
		if err := cmd.Run(); err != nil {
			t.Errorf("error executing pt-k8s-debug-collector: %s", err.Error())
		}

		defer func() {
			clean := exec.Command("rm", "-f", "cluster-dump.tar.gz")
			if err := clean.Run(); err != nil {
				t.Errorf("error cleaning up test data: %s", err.Error())
			}
		}()

		for _, test := range tests {
			if resource.env != test.env {
				continue
			}

			out, err := exec.Command(test.cmd[0], test.cmd[1:]...).CombinedOutput()
			if err != nil {
				t.Errorf("test %s, error running command %s:\n%s\nOutput:\n%s", test.name, test.cmd[0], err.Error(), out)
			}

			res := test.preprocessor(string(out))
			test.match.Match(t, res)
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
		resource   string
		want       string
		kubeconfig string
	}{
		{
			name:       "none",
			resource:   "none",
			want:       "0",
			kubeconfig: "",
		},
		{
			name:       "pxc",
			resource:   "pxc",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PXC"),
		},
		{
			name:       "ps",
			resource:   "ps",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PS"),
		},
		{
			name:       "psmdb",
			resource:   "psmdb",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PSMDB"),
		},
		{
			name:       "pg",
			resource:   "pg",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PG"),
		},
		{
			name:       "pgv2",
			resource:   "pgv2",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PG2"),
		},
		{
			name:       "auto pxc",
			resource:   "auto",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PXC"),
		},
		{
			name:       "auto ps",
			resource:   "auto",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PS"),
		},
		{
			name:       "auto psmdb",
			resource:   "auto",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PSMDB"),
		},
		{
			name:       "auto pg",
			resource:   "auto",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PG"),
		},
		{
			name:       "auto pgv2",
			resource:   "auto",
			want:       "3",
			kubeconfig: os.Getenv("KUBECONFIG_PG2"),
		},
	}

	for _, test := range tests {
		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", test.kubeconfig, "--forwardport", os.Getenv("FORWARDPORT"), "--resource", test.resource)
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

/*
PT-2299 - collect openssl x509 certificate information for each secret
*/
func TestSSLResourceOption(t *testing.T) {
	tests := []struct {
		name       string
		resource   string
		cmds       [][]string // slice of commands to execute
		want       []string   // slice of expected results
		kubeconfig string
	}{
		{
			name:     "auto pxc",
			resource: "auto",
			cmds: [][]string{
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-internal"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-internal"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-internal"},
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
			},
			want: []string{
				"ca.crt",
				"Certificate",
				"tls.crt",
				"ca.crt",
				"Certificate",
				"tls.crt",
				"ca.crt",
				"Certificate",
				"tls.crt",
			},
			kubeconfig: os.Getenv("KUBECONFIG_PXC"),
		},
		{
			name:     "auto ps",
			resource: "auto",
			cmds: [][]string{
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
			},
			want: []string{
				"ca.crt",
				"Certificate",
				"tls.crt",
				"ca.crt",
				"Certificate",
				"tls.crt",
			},
			kubeconfig: os.Getenv("KUBECONFIG_PS"),
		},
		{
			name:     "auto psmdb",
			resource: "auto",
			cmds: [][]string{
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl"},
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-internal"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-internal"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-internal"},
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ca-cert"},
			},
			want: []string{
				"ca.crt",
				"Certificate",
				"tls.crt",
				"ca.crt",
				"Certificate",
				"tls.crt",
				"ca.crt",
				"Certificate",
				"tls.crt",
			},
			kubeconfig: os.Getenv("KUBECONFIG_PSMDB"),
		},
		{
			name:     "auto pg",
			resource: "auto",
			cmds: [][]string{
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-ca"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-ca"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-keypair"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-ssl-keypair"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/pgo.tls"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/pgo.tls"},
			},
			want: []string{
				"ca.crt",
				"Certificate",
				"tls.crt\ntls.crt",
				"Certificate\nCertificate",
				"tls.crt",
				"Certificate",
			},
			kubeconfig: os.Getenv("KUBECONFIG_PG"),
		},
		{
			name:     "auto pgv2",
			resource: "auto",
			cmds: [][]string{
				{"tar", "--to-command", "grep -m 1 -o ca.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-cluster-cert"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-cluster-cert"},
				{"tar", "--to-command", "grep -m 1 -o tls.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*-cluster-cert"},
				{"tar", "--to-command", "grep -m 1 -o root.crt", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/pgo-root-cacert"},
				{"tar", "--to-command", "grep -m 1 -o Certificate", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/pgo-root-cacert"},
			},
			want: []string{
				"ca.crt",
				"Certificate",
				"tls.crt",
				"root.crt",
				"Certificate",
			},
			kubeconfig: os.Getenv("KUBECONFIG_PG2"),
		},
	}

	for _, test := range tests {
		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", test.kubeconfig, "--forwardport", os.Getenv("FORWARDPORT"), "--resource", test.resource)
		if err := cmd.Run(); err != nil {
			t.Errorf("error executing pt-k8s-debug-collector: %s", err.Error())
		}
		defer func() {
			cmd = exec.Command("rm", "-f", "cluster-dump.tar.gz")
			if err := cmd.Run(); err != nil {
				t.Errorf("error cleaning up test data: %s", err.Error())
			}
		}()
		for ind, testcmd := range test.cmds {
			out, err := exec.Command(testcmd[0], testcmd[1:]...).Output()
			if err != nil {
				t.Errorf("test %s, error running command %s:\n%s\n\nCommand output:\n%s", test.name, testcmd, err.Error(), out)
			}
			if strings.TrimRight(bytes.NewBuffer(out).String(), "\n") != test.want[ind] {
				t.Errorf("test %s, output is not as expected\nOutput: %s\nWanted: %s", test.name, out, test.want)
			}
		}
	}
}

/*
Tests for option --skip-pod-summary
*/
func TestPT_2453(t *testing.T) {
	testcmd := []string{"sh", "-c", "tar -tf cluster-dump.tar.gz --wildcards '*/summary.txt' 2>/dev/null | wc -l"}
	tests := []struct {
		name       string
		resource   string
		want       string
		kubeconfig string
	}{
		{
			name:       "none",
			resource:   "none",
			want:       "0",
			kubeconfig: "",
		},
		{
			name:       "pxc",
			resource:   "pxc",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PXC"),
		},
		{
			name:       "ps",
			resource:   "ps",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PS"),
		},
		{
			name:       "psmdb",
			resource:   "psmdb",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PSMDB"),
		},
		{
			name:       "pg",
			resource:   "pg",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PG"),
		},
		{
			name:       "pgv2",
			resource:   "pgv2",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PG2"),
		},
		{
			name:       "auto pxc",
			resource:   "auto",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PXC"),
		},
		{
			name:       "auto ps",
			resource:   "auto",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PS"),
		},
		{
			name:       "auto psmdb",
			resource:   "auto",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PSMDB"),
		},
		{
			name:       "auto pg",
			resource:   "auto",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PG"),
		},
		{
			name:       "auto pgv2",
			resource:   "auto",
			want:       "0",
			kubeconfig: os.Getenv("KUBECONFIG_PG2"),
		},
	}

	for _, test := range tests {
		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", test.kubeconfig, "--forwardport", os.Getenv("FORWARDPORT"), "--resource", test.resource, "--skip-pod-summary")
		if err := cmd.Run(); err != nil {
			t.Errorf("error executing pt-k8s-debug-collector: %s\nCommand: %s", err.Error(), cmd.String())
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

/*
Option --version
*/
func TestVersionOption(t *testing.T) {
	out, err := exec.Command("../../../bin/"+toolname, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(toolname + `\n.*Version v?\d+\.\d+\.\d+\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", toolname, out)
	}
}

/*
If we handle error properly
*/
func TestPT_2169(t *testing.T) {
	busyport, _ := os.Getwd() // we are using wrong socket for ssh tunnel here to ensure we get error

	testcmd := []string{"sh", "-c", "tar -xf cluster-dump.tar.gz --wildcards '*/summary.txt' --to-command 'grep stderr:' 2>/dev/null | wc -l"}
	tests := []struct {
		name       string
		resource   string
		want       string
		port       string
		kubeconfig string
	}{
		{
			name:       "pxc with busy port",
			resource:   "pxc",
			want:       "3",
			port:       busyport,
			kubeconfig: os.Getenv("KUBECONFIG_PXC"),
		},
		{
			name:       "pg no error",
			resource:   "pg",
			want:       "0",
			port:       os.Getenv("FORWARDPORT"),
			kubeconfig: os.Getenv("KUBECONFIG_PG"),
		},
	}

	for _, test := range tests {
		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", test.kubeconfig, "--forwardport", test.port, "--resource", test.resource)
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
