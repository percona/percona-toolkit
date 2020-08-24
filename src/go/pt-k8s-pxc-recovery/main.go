package main

import (
	"flag"
	"fmt"
	"log"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/recover"
)

func stepOrError(err error) {
	if err != nil {
		log.Fatal("Error:", err)
	}
}

func main() {
	namespace, clusterName, debugImage := "", "", ""
	flag.StringVar(&namespace, "namespace", "default", "Select the namespace in which the cluster is deployed in")
	flag.StringVar(&clusterName, "cluster", "test-cluster", "Select the cluster to recover")
	flag.StringVar(&debugImage, "debug-image", "percona/percona-xtradb-cluster:8.0.19-10.1-debug", "Name and version of the debug image to use")
	flag.Parse()
	c := recover.Cluster{Namespace: namespace, Name: clusterName}
	log.SetPrefix("\n" + log.Prefix())

	log.Printf("Starting recovery process")
	go func() {
		for {
			time.Sleep(300 * time.Millisecond)
			fmt.Print(".")
		}
	}()

	log.Printf("Getting cluster size")
	stepOrError(c.SetClusterSize())

	log.Printf("Getting cluster image")
	stepOrError(c.GetClusterImage())

	log.Printf("Confirming crashed status")
	stepOrError(c.ConfirmCrashedStatus())

	log.Printf("Patching cluster image")
	stepOrError(c.PatchClusterImage(debugImage))

	log.Printf("Restarting pods")
	stepOrError(c.RestartPods())

	log.Printf("Make sure pod zero is ready")
	stepOrError(c.PodZeroReady())

	log.Printf("Make sure all pods are running")
	stepOrError(c.AllPodsRunning())

	log.Print("Set SST in progress")
	stepOrError(c.SetSSTInProgress())

	log.Print("Waiting for all pods to be ready")
	stepOrError(c.AllPodsReady())

	log.Printf("Finding the most recent pod")
	stepOrError(c.FindMostRecentPod())

	log.Printf("Recovering most recent pod")
	go func() {
		err := c.RecoverMostRecentPod()
		if err != nil {
			log.Printf("Recovering most recent pod still in progress")
		}
	}()

	time.Sleep(10 * time.Second)

	log.Printf("Patching cluster image")
	stepOrError(c.PatchClusterImage(c.ClusterImage))

	log.Printf("Restart all pods execpt most recent pod")
	stepOrError(c.RestartAllPodsExceptMostRecent())

	log.Printf("Make sure all pods are running")
	stepOrError(c.AllPodsRunning())

	log.Printf("Restart Most Recent Pod")
	stepOrError(c.RestartMostRecentPod())

	log.Print("Waiting for all pods to be ready")
	stepOrError(c.AllPodsReady())

	log.Printf("Completed the restore process")
}
