package main

import (
	"flag"
	"log"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/helpers"
	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/recover"
)

func step(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func main() {
	namespace, clusterName := "", ""
	flag.StringVar(&namespace, "namespace", "default", "Select the namespace in which the cluster is deployed in")
	flag.StringVar(&clusterName, "cluster", "test-cluster", "Select the cluster to recover")
	flag.Parse()
	helpers.SetNamespace(namespace)
	recover.SetClusterName(clusterName)

	step(recover.SetClusterSize())
	step(recover.ConfirmCrashedStatus())
	step(recover.PatchClusterImage())
	step(recover.RestartPods())
}
