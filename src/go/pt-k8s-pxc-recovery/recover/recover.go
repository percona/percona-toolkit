package recover

import (
	"errors"
	"strings"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/helpers"
)

var clusterName = ""

func SetClusterName(name string) {
	if clusterName == "" {
		clusterName = name
	}
}

func ConfirmCrashedStatus() error {
	args := []string{
		"get",
		"pods",
	}
	out, err := helpers.RunCmd(args...)
	if err != nil {
		return err
	}
	formatedOutput := strings.Split(string(out), "\n")
	podNames := []string{}
	for _, v := range formatedOutput {
		podName := strings.Split(v, " ")[0]
		if strings.Contains(podName, clusterName) && strings.Contains(podName, "pxc") {
			podNames = append(podNames, podName)
		}
	}
	if len(podNames) > 1 {
		return errors.New("Cluster has more than one Pod up")
	}
	failedNodes := 0
	for _, pod := range podNames {
		logs, err := helpers.RunCmd("logs", pod)
		if err != nil {
			return err
		}
		if strings.Contains(string(logs), "grastate.dat") && strings.Contains(string(logs), "safe_to_bootstrap") {
			failedNodes++
		}
	}
	if len(podNames) != failedNodes {
		return errors.New("Not all cluster is down restart failed pods manually")
	}
	return nil
}
