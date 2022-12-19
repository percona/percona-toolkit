package main

import (
	"flag"
	"log"
	"os"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-debug-collector/dumper"
)

func main() {
	namespace := ""
	resource := ""
	clusterName := ""
	kubeconfig := ""
	forwardport := ""

	flag.StringVar(&namespace, "namespace", "", "Namespace for collecting data. If empty data will be collected from all namespaces")
	flag.StringVar(&resource, "resource", "none", "Collect data, specific to the resource. Supported values: pxc, psmdb, pg, ps, none")
	flag.StringVar(&clusterName, "cluster", "", "Cluster name")
	flag.StringVar(&kubeconfig, "kubeconfig", "", "Path to kubeconfig")
	flag.StringVar(&forwardport, "forwardport", "", "Port to use for  port forwarding")
	flag.Parse()

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
