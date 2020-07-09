package main

import (
	"flag"
	"log"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/helpers"
	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/recover"
)

func stepOrError(err error) {
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

	stepOrError(recover.SetClusterSize())
	stepOrError(recover.ConfirmCrashedStatus())
	stepOrError(recover.PatchClusterImage())
	stepOrError(recover.RestartPods())
	stepOrError(recover.PodZeroReady())
	stepOrError(recover.AllPodsRunning())
	stepOrError(recover.SetSSTInProgress())
	stepOrError(recover.AllPodsReady())
	stepOrError(recover.FindMostRecentPod())
}
