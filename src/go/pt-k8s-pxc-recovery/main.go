package main

import (
	"flag"
	"log"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/helpers"
	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/recover"
)

func main() {
	namespace, clusterName := "", ""
	flag.StringVar(&namespace, "namespace", "default", "Select the namespace in which the cluster is deployed in")
	flag.StringVar(&clusterName, "clustername", "test-cluster", "Select the cluster to recover")
	flag.Parse()
	helpers.SetNamespace(namespace)
	recover.SetClusterName(clusterName)
	err := recover.ConfirmCrashedStatus()
	if err != nil {
		log.Fatal(err)
	}
}
