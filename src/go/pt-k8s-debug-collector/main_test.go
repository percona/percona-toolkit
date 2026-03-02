// This program is copyright 2020-2026 Percona LLC and/or its affiliates.
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
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/percona/percona-toolkit/src/go/tests/utils"
	"github.com/spf13/pflag"
	"github.com/stretchr/testify/suite"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

/*
TEST PREREQUISITES:
  - Cluster State: All target clusters must be deployed and in a "Ready" state.
  - Required Namespaces: The test targets the following specific namespaces:
    "pxc", "ps", "psmdb", "pgo", "pgv2".
  - Connectivity: A valid kubeconfig must be provided with active contexts for each cluster.

AUTOMATIC DEPLOYMENT (Optional):
  If the environment is not ready, you can use k3d for automated setup.
  Note: Deployment may take time, so increasing the timeout is mandatory.

  Usage:
    go test ./... -timeout 60m --args --deploy-k3d [comma-separated-deployments]

  Available deployment targets:
    "pxc", "ps", "psmdb", "pgo", "pgv2"

  Example:
    go test ./... -timeout 60m --args --deploy pxc,pgv2

ENVIRONMENT VARIABLES:
  - KUBECONFIG:  Custom path to your kubeconfig file.
                 Default: $HOME/.kube/config
  - FORWARDPORT (Optional): Specifies a custom local port for port-forwarding to pods.
                 Use this if the default port is already bound or in use by another process.
*/

const (
	DEFAULT_FORWARD_PORT = "18443"
	TOOL_PATH            = "../../../bin/pt-k8s-debug-collector"
)

var (
	namespaces = []string{
		"pxc", "ps", "psmdb", "pgo", "pgv2",
	}

	resources = []string{
		"pxc", "ps", "psmdb", "pgo", "pgv2", "auto", "none",
	}
)

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

func getExistingNamespaces(ctx context.Context) []string {
	testNs := []string{}
	config, err := utils.GetKubeConfigPath()
	if err != nil {
		log.Printf("could not get a kubeconfig: %s", err)
		return testNs
	}

	kubeClient, err := getKubeClient(config)
	if err != nil {
		log.Printf("could not get a kubeclient: %s", err)
		return testNs
	}

	existingNs, _ := utils.GetNamespaces(ctx, kubeClient)
	for _, exNs := range existingNs {
		for _, ns := range namespaces {
			if ns == exNs {
				testNs = append(testNs, ns)
			}
		}
	}

	return testNs
}

var (
	selectedDeploymentNames        []string
	selectedDeploymentNamesChanged bool
	testNamespaces                 []string
)

func init() {
	pflag.StringSliceVar(&selectedDeploymentNames, "deploy-k3d", namespaces, fmt.Sprintf("Select a specific deployments to test against. Avaliable deployments: %s", strings.Join(namespaces, ",")))
}

func TestMain(m *testing.M) {
	pflag.CommandLine.AddGoFlagSet(flag.CommandLine)
	pflag.Parse()
	pflag.ParseSkippedFlags(os.Args[1:], flag.CommandLine)

	selectedDeploymentNamesChanged = pflag.Lookup("deploy-k3d").Changed

	ctx := context.Background()

	testNamespaces = getExistingNamespaces(ctx)

	if len(testNamespaces) != 0 && selectedDeploymentNamesChanged {
		log.Fatalf("You already have runing clusters in this namespaces: %s, use --deploy-k3d only with zero init configuration", testNamespaces)
	}

	if len(testNamespaces) == 0 && !selectedDeploymentNamesChanged {
		log.Fatalf(`Target namespaces not found in the cluster.
    
Expected one of: %s
Found in cluster: %s

Possible reasons:
1. The cluster hasn't been deployed yet.
2. Your kubeconfig does not contains proper contexts

Action: Run tests with the "--deploy-k3d" flag to automatically set up the required environment.`,
			strings.Join(namespaces, ", "), strings.Join(testNamespaces, ", "))
	}

	log.Printf("Starting tests for deployments: %s\n", strings.Join(testNamespaces, ","))

	exitCode := m.Run()
	os.Exit(exitCode)
}

type CollectorSuite struct {
	suite.Suite
	KubeConfig  string
	KubeClient  kubernetes.Interface
	Namespace   string
	ForwardPort string
	Resources   []string
}

func (s *CollectorSuite) SetupSuite() {
	if selectedDeploymentNamesChanged {
		rawConfig, err := utils.DeployK3d(s.T().Context(), s.Namespace)
		if err != nil {
			s.Require().NoError(err)
			return
		}

		tmpFile, err := os.CreateTemp("", "kubeconfig-*.yaml")
		if err != nil {
			s.Require().NoError(err)
			return
		}

		_, err = tmpFile.WriteString(rawConfig)
		if err != nil {
			s.Require().NoError(err)
			return
		}
		tmpFile.Close()

		s.KubeConfig = tmpFile.Name()

		client, _, err := utils.GetKubeClientFromRaw(rawConfig, "k3d-"+s.Namespace)
		if err != nil {
			s.Require().NoError(err)
			return
		}
		s.KubeClient = client
	}

	stsCtx, stsCancel := context.WithTimeout(s.T().Context(), 2*time.Minute)
	defer stsCancel()

	err := utils.WaitForAllStatefulSetReady(stsCtx, s.KubeClient, s.Namespace)
	if err != nil {
		s.T().Logf("failed to wait for STS: %s, skipping", err)
	}

	podCtx, podCancel := context.WithTimeout(s.T().Context(), 60*time.Minute)
	defer podCancel()

	s.Require().NoError(utils.WaitForAllPodsReady(podCtx, s.KubeClient, s.Namespace))
}

func (s *CollectorSuite) TearDownSuite() {
	if selectedDeploymentNamesChanged {
		s.T().Logf("Cleaning up %s", s.Namespace)
		utils.DestroyK3d(s.T().Context(), s.Namespace)
	}
}

func (s *CollectorSuite) TearDownTest() {
	_ = os.Remove("cluster-dump.tar.gz")
}

func TestCollectorRunner(t *testing.T) {
	config, _ := utils.GetKubeConfigPath()
	client, _ := getKubeClient(config)

	ns := selectedDeploymentNames
	if len(testNamespaces) != 0 {
		ns = testNamespaces
	}

	for _, name := range ns {
		t.Run("Operator_"+name, func(t *testing.T) {
			fport := strings.TrimSpace(os.Getenv("FORWARDPORT"))
			if fport == "" {
				fport = DEFAULT_FORWARD_PORT
			}

			suite.Run(t, &CollectorSuite{
				KubeConfig:  config,
				KubeClient:  client,
				Namespace:   name,
				ForwardPort: fport,
				Resources:   []string{name, "auto", "none"},
			})
		})
	}
}

func TestVersionOption(t *testing.T) {
	out, err := exec.Command(TOOL_PATH, "--version").Output()
	if err != nil {
		t.Errorf("error executing %s --version: %s", toolname, err.Error())
	}
	// We are using MustCompile here, because hard-coded RE should not fail
	re := regexp.MustCompile(toolname + `\n.*Version v?\d+\.\d+\.\d+\n`)
	if !re.Match(out) {
		t.Errorf("%s --version returns wrong result:\n%s", toolname, out)
	}
}

func (s *CollectorSuite) TestIndividualFiles() {
	tests := []struct {
		namespace    string
		name         string
		cmd          []string
		want         []string
		preprocessor func(string) string
	}{
		{
			namespace: "pxc",
			// If the tool collects required log files
			name: "pxc_logs_list",
			// tar -tf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/*'
			cmd:  []string{"tar", "-tf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/*"},
			want: []string{"auto.cnf", "grastate.dat", "gvwstate.dat", "innobackup.backup.log", "innobackup.move.log", "innobackup.prepare.log", "mysqld-error.log", "mysqld.post.processing.log"},
			preprocessor: func(in string) string {
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
			namespace: "pxc",
			// If MySQL error log is not empty
			name: "pxc_mysqld_error_log",
			// tar --to-command="grep -m 1 -o Version:" -xzf cluster-dump-test.tar.gz --wildcards 'cluster-dump/*/var/lib/mysql/mysqld-error.log'
			cmd:  []string{"tar", "--to-command", "grep -m 1 -o Version:", "-xzf", "cluster-dump.tar.gz", "--wildcards", "cluster-dump/*/var/lib/mysql/mysqld-error.log"},
			want: []string{"Version:"},
			preprocessor: func(in string) string {
				nl := strings.Index(in, "\n")
				if nl == -1 {
					return ""
				}
				return in[:nl]
			},
		},
	}

	if s.Namespace != "pxc" {
		s.T().Skip("This test is specifically for pxc namespace")
	}

	for _, resource := range s.Resources {
		s.Run("Resource_"+resource, func() {
			cmd := exec.Command(TOOL_PATH, "--kubeconfig", s.KubeConfig, "--forwardport", s.ForwardPort, "--resource", resource)
			err := cmd.Run()
			s.NoError(err)

			for _, test := range tests {
				out, err := exec.Command(test.cmd[0], test.cmd[1:]...).CombinedOutput()
				if err != nil && resource == "none" {
					continue
				}
				s.NoError(err)
				if test.preprocessor(bytes.NewBuffer(out).String()) != strings.Join(test.want, "\n") {
					s.Failf("Preprocessor Check", "test %s\nresource:%s\nnamespace: %s\noutput is not as expected\nOutput: %s\nWanted: %s", test.name, resource, test.namespace, test.preprocessor(bytes.NewBuffer(out).String()), test.want)
				}
			}
		})
	}
}

func (s *CollectorSuite) TestResourceOption() {
	testcmd := []string{"sh", "-c", "tar -tf cluster-dump.tar.gz --wildcards '*/summary.txt' 2>/dev/null | wc -l"}
	tests := []struct {
		name      string
		namespace string
		skip      bool
		want      string
	}{
		{name: "pxc", namespace: "pxc", want: "3"},
		{name: "ps", namespace: "ps", want: "3"},
		{name: "psmdb", namespace: "psmdb", want: "3"},
		{name: "pg", namespace: "pg", want: "3"},
		{name: "pgv2", namespace: "pgv2", want: "3"},
	}

	for _, resource := range s.Resources {
		s.Run("Resource_"+resource, func() {
			cmd := exec.Command(TOOL_PATH, "--kubeconfig", s.KubeConfig, "--forwardport", s.ForwardPort, "--resource", resource)
			err := cmd.Run()
			s.NoError(err)

			for _, test := range tests {
				if test.namespace != s.Namespace {
					continue
				}

				if resource == "none" {
					test.want = "0"
				}

				out, err := exec.Command(testcmd[0], testcmd[1:]...).Output()
				s.NoErrorf(err, "test %s, error running command %s\nCommand output:\n%s", test.name, testcmd, out)
				if strings.TrimRight(bytes.NewBuffer(out).String(), "\n") != test.want {
					s.Failf("Summary Check", "test %s\nresource %s\nnamespace %s\noutput is not as expected\nOutput: %s\nWanted: %s", test.name, resource, test.namespace, out, test.want)
				}
			}
		})
	}
}

func (s *CollectorSuite) TestPT_2453() {
	testcmd := []string{"sh", "-c", "tar -tf cluster-dump.tar.gz --wildcards '*/summary.txt' 2>/dev/null | wc -l"}
	tests := []struct {
		name      string
		namespace string
		skip      bool
		want      string
	}{
		{name: "pxc", namespace: "pxc", want: "0"},
		{name: "ps", namespace: "ps", want: "0"},
		{name: "psmdb", namespace: "psmdb", want: "0"},
		{name: "pg", namespace: "pg", want: "0"},
		{name: "pgv2", namespace: "pgv2", want: "0"},
	}

	for _, resource := range s.Resources {
		s.Run("Resource_"+resource, func() {
			cmd := exec.Command(TOOL_PATH,
				"--kubeconfig", s.KubeConfig,
				"--forwardport", s.ForwardPort,
				"--resource", resource,
				"--skip-pod-summary")
			err := cmd.Run()
			s.NoError(err)

			for _, test := range tests {
				if test.namespace != s.Namespace {
					continue
				}

				out, err := exec.Command(testcmd[0], testcmd[1:]...).Output()
				s.NoErrorf(err, "test %s, error running command %s\nCommand output:\n%s", test.name, testcmd, out)
				if strings.TrimRight(bytes.NewBuffer(out).String(), "\n") != test.want {
					s.Failf("Summary Check", "test %s\nresource %s\nnamespace %s\noutput is not as expected\nOutput: %s\nWanted: %s", test.name, resource, test.namespace, out, test.want)
				}
			}
		})
	}
}

var busyPortTested bool

// PT-2169
func (s *CollectorSuite) TestBusyPortError() {
	if s.Namespace == "pgv2" {
		s.Run("pg_gather_no_error", func() {
			cmd := exec.Command(TOOL_PATH,
				"--kubeconfig", s.KubeConfig,
				"--forwardport", s.ForwardPort,
				"--resource", s.Namespace,
			)

			_ = cmd.Run()
			testcmd := "tar -xf cluster-dump.tar.gz --wildcards \"*/summary.txt\" --to-command 'grep \"err: strconv.ParseInt\"' | wc -l"
			out, err := exec.Command("sh", "-c", testcmd).Output()

			s.NoError(err)
			s.Equal("0", strings.TrimSpace(string(out)), "Should not find error logs in summary files")
		})
	}

	if busyPortTested {
		s.T().Skip("Already tested in another namespace run")
	}

	busyPortTested = true

	s.Run("strconv_error_on_busy_port", func() {
		busyPort, _ := os.Getwd()

		cmd := exec.Command(TOOL_PATH,
			"--kubeconfig", s.KubeConfig,
			"--forwardport", busyPort,
			"--resource", s.Namespace,
		)

		_ = cmd.Run()
		testcmd := "tar -xf cluster-dump.tar.gz --wildcards \"*/summary.txt\" --to-command 'grep \"err: strconv.ParseInt\"' | wc -l"
		out, err := exec.Command("sh", "-c", testcmd).Output()

		s.NoError(err)
		s.Equal("3", strings.TrimSpace(string(out)), "Should find error logs in summary files due to busy port")
	})
}

type CmdCompare struct {
	cmd []string
	out string
}

func PreareFindFileInTarCmd(tarPath, filePath, substring string) []string {
	return []string{"sh", "-c", fmt.Sprintf("tar -xzf %s --wildcards %s -O | grep -o %s", tarPath, filePath, substring)}
}

/*
PT-2299 - collect openssl x509 certificate information for each secret
*/
func (s *CollectorSuite) TestSSLResourceOption() {
	tests := []struct {
		name      string
		namespace string
		cmdOut    []CmdCompare
	}{
		{
			name: "pxc", namespace: "pxc", cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pxc/*-ssl", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pxc/*-ssl", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pxc/*-ssl-internal", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pxc/*-ssl-internal", "tls.crt"), "tls.crt"},
			},
		},
		{
			name: "ps", namespace: "ps", cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/ps/*-ssl", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/ps/*-ssl", "tls.crt"), "tls.crt"},
			},
		},
		{
			name: "psmdb", namespace: "psmdb", cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/psmdb/*-ssl", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/psmdb/*-ssl", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/psmdb/*-ssl-internal", "ca.crt"), "ca.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/psmdb/*-ssl-internal", "tls.crt"), "tls.crt"},
			},
		},
		{
			name: "pgo", namespace: "pgo", cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pgo/*-ssl-keypair", "tls.crt"), strings.Repeat("tls.crt", 2)}, // there are two files with tls.crt
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pgo/*.tls", "tls.crt"), "tls.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pgo/*-ssl-ca", "ca.crt"), "ca.crt"},
			},
		},
		{
			name: "pgv2", namespace: "pgv2", cmdOut: []CmdCompare{
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pgv2/*-ca-cert", "root.crt"), "root.crt"},
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pgv2/*-cert", "tls.crt"), strings.Repeat("tls.crt", 2)}, // there are two files with tls.crt
				{PreareFindFileInTarCmd("cluster-dump.tar.gz", "cluster-dump/pgv2/*-cert", "ca.crt"), strings.Repeat("ca.crt", 2)},   // there are two files with ca.crt
			},
		},
	}

	for _, resource := range s.Resources {
		s.Run("Resource_"+resource, func() {
			cmd := exec.Command(TOOL_PATH,
				"--kubeconfig", s.KubeConfig,
				"--forwardport", s.ForwardPort,
				"--resource", resource,
				"--skip-pod-summary")
			err := cmd.Run()
			s.NoError(err)

			for _, test := range tests {
				if test.namespace != s.Namespace {
					continue
				}

				for _, testcmd := range test.cmdOut {
					out, err := exec.Command(testcmd.cmd[0], testcmd.cmd[1:]...).Output()
					s.NoErrorf(err, "test %s, error running command %s\nCommand output:\n%s", test.name, testcmd, out)
					if strings.Replace(bytes.NewBuffer(out).String(), "\n", "", -1) != testcmd.out {
						s.Failf("SSL Metadata check", "test %s, output is not as expected\nOutput: %s\nWanted: %s", test.name, out, testcmd.out)
					}
				}
			}
		})
	}
}
