package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-debug-collector/dumper"
)

const (
	TOOLNAME = "pt-k8s-debug-collector"
)

// We do not set anything here, these variables are defined by the Makefile
var (
	Build     string
	GoVersion string
	Version   string
	Commit    string
)

func main() {
	namespace := ""
	resource := ""
	clusterName := ""
	kubeconfig := ""
	forwardport := ""
	version := false

	flag.StringVar(&namespace, "namespace", "", "Namespace for collecting data. If empty data will be collected from all namespaces")
	flag.StringVar(&resource, "resource", "none", "Collect data, specific to the resource. Supported values: pxc, psmdb, pg, ps, none")
	flag.StringVar(&clusterName, "cluster", "", "Cluster name")
	flag.StringVar(&kubeconfig, "kubeconfig", "", "Path to kubeconfig")
	flag.StringVar(&forwardport, "forwardport", "", "Port to use for  port forwarding")
	flag.BoolVar(&version, "version", false, "Print version")
	flag.Parse()

	if version {
		fmt.Println(TOOLNAME)
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)

		return
	}

	if len(clusterName) > 0 {
		resource += "/" + clusterName
	}

	d := dumper.New("", namespace, resource, kubeconfig, forwardport)
	log.Println("Start collecting cluster data")

	err := d.DumpCluster()
	if err != nil {
		log.Println("Error:", err)
		os.Exit(1)
	}

	log.Println("Done")
}
