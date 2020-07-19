package main

import (
	"flag"
	"log"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/recover"
)

func stepOrError(err error) {
	if err != nil {
		log.Fatal("Error:", err)
	}
}

func main() {
	namespace, clusterName := "", ""
	flag.StringVar(&namespace, "namespace", "default", "Select the namespace in which the cluster is deployed in")
	flag.StringVar(&clusterName, "cluster", "test-cluster", "Select the cluster to recover")
	flag.Parse()
	c := recover.Cluster{Namespace: namespace, Name: clusterName}

	stepOrError(c.SetClusterSize())
	stepOrError(c.ConfirmCrashedStatus())
	stepOrError(c.PatchClusterImage())
	stepOrError(c.RestartPods())
	stepOrError(c.PodZeroReady())
	stepOrError(c.AllPodsRunning())
	stepOrError(c.SetSSTInProgress())
	stepOrError(c.AllPodsReady())
	stepOrError(c.FindMostRecentPod())
}
