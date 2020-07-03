package main

import (
	"flag"
	"log"
	"os"

	"github.com/percona/percona-toolkit/src/go/debug-collector/dumper"
)

func main() {
	namespace := ""
	resource := ""
	clusterName := ""

	flag.StringVar(&namespace, "namespace", "", "Namespace for dumping. If empty will dump all namespaces")
	flag.StringVar(&resource, "resource", "pxc", "Resource name. Default value - 'pxc'")
	flag.StringVar(&clusterName, "cluster", "", "Cluster name")
	flag.Parse()

	if len(clusterName) > 0 {
		resource = resource + "/" + clusterName
	}

	d := dumper.New("", namespace, resource)
	log.Println("Start dump cluster")

	err := d.DumpCluster()
	if err != nil {
		log.Println(err)
		os.Exit(1)
	}

	log.Println("Cluster dump ready")
}
