package recover

import (
	"errors"
	"strconv"
	"strings"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/helpers"
)

var clusterName = ""
var clusterSize = 0

func SetClusterSize() error {
	args := []string{
		"get",
		"pxc",
		clusterName,
		"-o",
		"jsonpath='{.spec.pxc.size}')",
	}
	strSize, err := helpers.RunCmd(args...)
	if err != nil {
		return err
	}
	// strSize = "3"
	clusterSize, err = strconv.Atoi(string(strSize))
	if err != nil {
		return err
	}
	return nil
}

func SetClusterName(name string) {
	if clusterName == "" {
		clusterName = name
	}
}

func getPods() ([]string, error) {
	args := []string{
		"get",
		"pods",
	}
	out, err := helpers.RunCmd(args...)
	if err != nil {
		return []string{}, err
	}
	formatedOutput := strings.Split(string(out), "\n")
	podNames := []string{}
	for _, v := range formatedOutput {
		podName := strings.Split(v, " ")[0]
		if strings.Contains(podName, clusterName) && strings.Contains(podName, "pxc") {
			podNames = append(podNames, podName)
		}
	}
	return podNames, nil
}

func ConfirmCrashedStatus() error {
	podNames, err := getPods()
	if err != nil {
		return err
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

func PatchClusterImage() error {
	args := []string{
		"patch",
		"pxc",
		clusterName,
		"--type=\"merge\"",
		"-p",
		"'{\"spec\":{\"pxc\":{\"image\":\"percona/percona-xtradb-cluster-operator:1.4.0-pxc8.0-debug\"}}}'",
	}
	_, err := helpers.RunCmd(args...)
	if err != nil {
		return err
	}
	return nil
}

func RestartPods() error {
	for i := 0; i < clusterSize; i++ {
		args := []string{
			"delete",
			"pod",
			clusterName + "-pxc-" + strconv.Itoa(i),
			"--force",
			"--grace-period=0",
		}
		_, err := helpers.RunCmd(args...)
		if err != nil {
			return err
		}
	}
	return nil
}
