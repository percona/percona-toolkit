package main

import (
	"fmt"
	"os"

	flag "github.com/spf13/pflag"

	log "github.com/sirupsen/logrus"

	"github.com/percona/percona-toolkit/src/go/lib/config"
	"github.com/percona/percona-toolkit/src/go/lib/versioncheck"
	"github.com/percona/percona-toolkit/src/go/pt-k8s-debug-collector/dumper"
	"github.com/percona/percona-toolkit/src/go/tests/utils"
)

const (
	toolname = "pt-k8s-debug-collector"
)

// We do not set anything here, these variables are defined by the Makefile
var (
	Build     string //nolint
	GoVersion string //nolint
	Version   string //nolint
	Commit    string //nolint
)

type cliOptions struct {
	namespace      string
	resource       string
	clusterName    string
	kubeconfig     string
	forwardport    string
	logLevelStr    string
	version        bool
	noVersionCheck bool
	skipPodSummary bool
}

func (opts *cliOptions) parseDefaultConfig() {
	conf := config.DefaultConfig(toolname)
	if val := conf.GetString("namespace"); val != "" && !flag.Lookup("namespace").Changed {
		opts.namespace = val
	}
	if val := conf.GetString("resource"); val != "" && !flag.Lookup("resource").Changed {
		opts.resource = val
	}
	if val := conf.GetString("cluster"); val != "" && !flag.Lookup("cluster").Changed {
		opts.clusterName = val
	}
	if val := conf.GetString("kubeconfig"); val != "" && !flag.Lookup("kubeconfig").Changed {
		opts.kubeconfig = val
	}
	if val := conf.GetString("forwardport"); val != "" && !flag.Lookup("forwardport").Changed {
		opts.forwardport = val
	}
	if val := conf.GetString("log-level"); val != "" && !flag.Lookup("log-level").Changed {
		opts.logLevelStr = val
	}

	if val := conf.GetBool("no-version-check"); !flag.Lookup("no-version-check").Changed {
		opts.noVersionCheck = val
	}

	if val := conf.GetBool("skip-pod-summary"); !flag.Lookup("skip-pod-summary").Changed {
		opts.skipPodSummary = val
	}
}

func main() {
	opts := cliOptions{}

	flag.StringVar(&opts.namespace, "namespace", "", "Namespace for collecting data. If empty data will be collected from all namespaces")
	flag.StringVar(&opts.resource, "resource", "auto", "Collect data, specific to the resource. Supported values: pxc, psmdb, pg, pgv2, ps, none, auto")
	flag.StringVar(&opts.clusterName, "cluster", "", "Cluster name")
	flag.StringVar(&opts.kubeconfig, "kubeconfig", "", "Path to kubeconfig")
	flag.StringVar(&opts.forwardport, "forwardport", "", "Port to use for  port forwarding")
	flag.StringVar(&opts.logLevelStr, "log-level", "error", "Log level (debug, info, warn, error, fatal, panic)")
	flag.BoolVar(&opts.version, "version", false, "Print version")
	flag.BoolVar(&opts.skipPodSummary, "skip-pod-summary", false, "Skip pod summary collection")
	flag.BoolVar(&opts.noVersionCheck, "no-version-check", false, "Default: Don't check for updates")
	flag.Parse()

	opts.parseDefaultConfig()

	if opts.version {
		fmt.Println(toolname)
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)

		return
	}

	if !opts.noVersionCheck {
		advice, err := versioncheck.CheckUpdates(toolname, Version)
		if err != nil {
			log.Infof("cannot check version updates: %s", err.Error())
		} else if advice != "" {
			log.Warn(advice)
		}
	}

	if len(opts.clusterName) > 0 {
		opts.resource += "/" + opts.clusterName
	}

	level, err := log.ParseLevel(opts.logLevelStr)
	if err != nil {
		fmt.Printf("Invalid log level: %v\n", err)
		os.Exit(1)
	}
	log.SetLevel(level)

	log.SetFormatter(&log.TextFormatter{
		FullTimestamp: true,
		DisableColors: true,
	})

	if !flag.Lookup("kubeconfig").Changed {
		path, err := utils.GetKubeConfigPath()
		if err != nil {
			log.Errorf("Failed to get default kubeconfig: %s", err)
		}

		opts.kubeconfig = path
	}

	d, err := dumper.New("cluster-dump", opts.namespace, opts.kubeconfig, opts.forwardport, opts.resource, opts.skipPodSummary)
	if err != nil {
		log.Error(err)
		os.Exit(1)
	}
	log.Info("start collecting cluster data")

	err = d.DumpCluster()
	if err != nil {
		log.Error(err)
		os.Exit(1)
	}

	log.Info("done")
}
