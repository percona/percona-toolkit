package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path"
	"regexp"
	"slices"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/percona/percona-toolkit/src/go/tests/utils"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
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
*/
var (
	namespaces = []string{
		"pxc", "ps", "psmdb", "pg", "pgv2",
	}

	resources = []string{
		"pxc", "ps", "psmdb", "pg", "pgv2", "auto", "none",
	}

	deployments = []string{
		"k8s-pxc:1.18.0", "k8s-ps:1.0.0", "k8s-psmdb:1.21.1", "k8s-pg:1.6.0", "k8s-pg:2.8.0",
	}
)

/*
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

// You need to have anydbver in path to start tests (https://github.com/ihanick/anydbver)

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

func getKubeClient(kubeconfigPath string) (kubernetes.Interface, error) {
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	if err != nil {
		return nil, err
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, err
	}

	return clientset, nil
}

func TestMain(m *testing.M) {
	ctx := context.Background()
	log.Println("START")
	args := []string{"deploy"}
	args = append(args, deployments...)
	utils.DeployAnyDbVer(ctx, args)

	config, err := utils.GetKubeConfigPath()
	if err != nil {
		log.Fatalf("could not get a kubeconfig: %s", err)
	}

	kubeClient, err := getKubeClient(config)
	if err != nil {
		log.Fatalf("could not get a kubeclient: %s", err)
	}

	for _, ns := range namespaces {
		cctx, _ := context.WithTimeout(ctx, time.Minute*10)

		err = utils.WaitForAllStatefulSetReady(cctx, kubeClient, ns)
		if err != nil {
			log.Fatalf("waiting for all statefullsets to be ready is falied with err: %s", err)
		}

		err = utils.WaitForAllPodsReady(cctx, kubeClient, ns)
		if err != nil {
			log.Fatalf("waiting for all pods to be ready is falied with err: %s", err)
		}
	}

	exitCode := m.Run()
	if exitCode == 0 {
		log.Println("Tests finished succesfully, destroying deployments")
		// Comment this if you don't want to destroy deployments after tests
		err := utils.CleanUpAnyDbVer(ctx)
		if err != nil {
			log.Fatalf("there was an error when destroying deloyments: %v", err)
		}
	}
	os.Exit(exitCode)
}

/*
   Tests collection of the individual files by pt-k8s-debug-collector.
   Requires running K8SPXC instance and kubectl, configured to access that instance by default.
   If some of the env (KUBECONFIG_PXC, KUBECONFIG_PG) is not defined, theese tests will be skiped.
*/

func TestIndividualFiles(t *testing.T) {
	config, err := utils.GetKubeConfigPath()
	if err != nil {
		t.Fatalf("error getting config for kube: %v", err)
	}

	tests := []struct {
		name         string
		cmd          []string
		resource     string
		preprocessor func(string) string
		match        Matcher
	}{
		{
			// If the tool collects required mysql log files
			name: "pxc_logs_list",
			// tar -tf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/*'
			cmd:          []string{"tar", "-tf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/*"},
			preprocessor: uniqueBasenames,
			resource:     "pxc",
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
			name:     "pxc_mysqld_error_log",
			resource: "pxc",
			// tar --to-command="grep -m 1 -o Version:" -xzf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/mysqld-error.log'
			cmd:          []string{"tar", "--to-command", "grep -m 1 -o Version:", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/mysqld-error.log"},
			preprocessor: firstLine,
			match: ExactMatch{
				Want: []string{"Version:"},
			},
		},
		{
			// if the tool collects required pg log files
			name:         "pg_logs_list",
			resource:     "pg",
			cmd:          []string{"tar", "-tf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/*/pg_log/*"},
			preprocessor: uniqueBasenames,
			match: RegexMatch{
				Pattern: regexp.MustCompile(`^postgresql-[A-Za-z]{3}\.log$`),
			},
		},
	}

	requestedClusterReports := make(map[string]struct{}, 0)
	for _, test := range tests {
		requestedClusterReports[test.resource] = struct{}{}
	}

	for resource := range requestedClusterReports {
		cmd := exec.Command("../../../bin/pt-k8s-debug-collector",
			"--kubeconfig", config,
			"--forwardport", os.Getenv("FORWARDPORT"),
			"--resource", resource,
		)
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
			if !slices.Contains(resources, test.resource) {
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
	config, err := utils.GetKubeConfigPath()
	if err != nil {
		t.Fatalf("error getting config for kube: %v", err)
	}
	testcmd := []string{"sh", "-c", "tar -tf cluster-dump.tar.gz --wildcards '*/summary.txt' 2>/dev/null | wc -l"}
	tests := []struct {
		name     string
		resource string
		want     string
	}{
		{
			name:     "none",
			resource: "none",
			want:     "0",
		},
		{
			name:     "pxc",
			resource: "pxc",
			want:     "3",
		},
		{
			name:     "ps",
			resource: "ps",
			want:     "3",
		},
		{
			name:     "psmdb",
			resource: "psmdb",
			want:     "3",
		},
		{
			name:     "pg",
			resource: "pg",
			want:     "3",
		},
		{
			name:     "pgv2",
			resource: "pgv2",
			want:     "3",
		},
		{
			name:     "auto pxc",
			resource: "auto",
			want:     "3",
		},
		{
			name:     "auto ps",
			resource: "auto",
			want:     "3",
		},
		{
			name:     "auto psmdb",
			resource: "auto",
			want:     "3",
		},
		{
			name:     "auto pg",
			resource: "auto",
			want:     "3",
		},
		{
			name:     "auto pgv2",
			resource: "auto",
			want:     "3",
		},
	}

	for _, test := range tests {
		if !slices.Contains(resources, test.resource) {
			continue
		}

		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", config, "--forwardport", os.Getenv("FORWARDPORT"), "--resource", test.resource)
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

type CmdCompare struct {
	cmd []string
	out string
}

func PreareFindFileInTarCmd(tarPath, filePath, substring string) []string {
	return []string{"tar", "--to-command", fmt.Sprintf("grep -m 1 -o %s", substring), "-xzf", tarPath, "--wildcards", filePath}
}

/*
PT-2299 - collect openssl x509 certificate information for each secret
*/
func TestSSLResourceOption(t *testing.T) {
	config, err := utils.GetKubeConfigPath()
	if err != nil {
		t.Fatalf("error getting config for kube: %v", err)
	}
	tests := []struct {
		name     string
		resource string
		cmdOut   []CmdCompare
	}{
		{
			name:     "auto pxc",
			resource: "auto",
			cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl-internal", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl-internal", "tls.crt"), "tls.crt"},
			},
		},
		{
			name:     "auto ps",
			resource: "auto",
			cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl", "tls.crt"), "tls.crt"},
			},
		},
		{
			name:     "auto psmdb",
			resource: "auto",
			cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl-internal", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl-internal", "tls.crt"), "tls.crt"},
			},
		},
		{
			name:     "auto pg",
			resource: "auto",
			cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl-keypair", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-pgo.tls", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ssl-ca", "ca.crt"), "ca.crt"},
			},
		},
		{
			name:     "auto pgv2",
			resource: "auto",
			cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-ca-cert", "root.crt"), "root.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-cert", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/*/secrets/*-cert", "ca.crt"), "ca.crt"},
			},
		},
	}

	for _, test := range tests {
		if !slices.Contains(resources, test.resource) {
			continue
		}
		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", config, "--forwardport", os.Getenv("FORWARDPORT"), "--resource", test.resource)
		if err := cmd.Run(); err != nil {
			t.Errorf("error executing pt-k8s-debug-collector: %s", err.Error())
		}
		defer func() {
			cmd = exec.Command("rm", "-f", "cluster-dump.tar.gz")
			if err := cmd.Run(); err != nil {
				t.Errorf("error cleaning up test data: %s", err.Error())
			}
		}()
		for _, testcmd := range test.cmdOut {
			out, err := exec.Command(testcmd.cmd[0], testcmd.cmd[1:]...).Output()
			if err != nil {
				t.Errorf("test %s, error running command %s:\n%s\n\nCommand output:\n%s", test.name, testcmd, err.Error(), out)
			}
			if strings.TrimRight(bytes.NewBuffer(out).String(), "\n") != testcmd.out {
				t.Errorf("test %s, output is not as expected\nOutput: %s\nWanted: %s", test.name, out, testcmd.out)
			}
		}
	}
}

/*
Tests for option --skip-pod-summary
*/
func TestPT_2453(t *testing.T) {
	config, err := utils.GetKubeConfigPath()
	if err != nil {
		t.Fatalf("error getting config for kube: %v", err)
	}
	testcmd := []string{"sh", "-c", "tar -tf cluster-dump.tar.gz --wildcards '*/summary.txt' 2>/dev/null | wc -l"}
	tests := []struct {
		name     string
		resource string
		want     string
	}{
		{
			name:     "none",
			resource: "none",
			want:     "0",
		},
		{
			name:     "pxc",
			resource: "pxc",
			want:     "0",
		},
		{
			name:     "ps",
			resource: "ps",
			want:     "0",
		},
		{
			name:     "psmdb",
			resource: "psmdb",
			want:     "0",
		},
		{
			name:     "pg",
			resource: "pg",
			want:     "0",
		},
		{
			name:     "pgv2",
			resource: "pgv2",
			want:     "0",
		},
		{
			name:     "auto pxc",
			resource: "auto",
			want:     "0",
		},
		{
			name:     "auto ps",
			resource: "auto",
			want:     "0",
		},
		{
			name:     "auto psmdb",
			resource: "auto",
			want:     "0",
		},
		{
			name:     "auto pg",
			resource: "auto",
			want:     "0",
		},
		{
			name:     "auto pgv2",
			resource: "auto",
			want:     "0",
		},
	}

	for _, test := range tests {
		if !slices.Contains(resources, test.resource) {
			continue
		}

		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", config, "--forwardport", os.Getenv("FORWARDPORT"), "--resource", test.resource, "--skip-pod-summary")
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
	config, err := utils.GetKubeConfigPath()
	if err != nil {
		t.Fatalf("error getting config for kube: %v", err)
	}
	busyport, _ := os.Getwd() // we are using wrong socket for ssh tunnel here to ensure we get error

	testcmd := []string{"sh", "-c", `tar -xf cluster-dump.tar.gz --wildcards "*/summary.txt" --to-command 'grep -m1 "err: strconv.ParseInt"' 2>/dev/null | wc -l`}
	tests := []struct {
		name     string
		resource string
		want     string
		port     string
	}{
		{
			name:     "pxc with busy port",
			resource: "pxc",
			want:     "3",
			port:     busyport,
		},
		{
			name:     "pg no error",
			resource: "pg",
			want:     "0",
			port:     os.Getenv("FORWARDPORT"),
		},
	}

	for _, test := range tests {
		if !slices.Contains(resources, test.resource) {
			continue
		}

		cmd := exec.Command("../../../bin/pt-k8s-debug-collector", "--kubeconfig", config, "--forwardport", test.port, "--resource", test.resource)
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
