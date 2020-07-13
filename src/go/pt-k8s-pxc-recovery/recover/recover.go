package recover

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/helpers"
)

var clusterName = ""
var clusterSize = 0
var mostRecentPod int

func SetClusterSize() error {
	args := []string{
		"get",
		"pxc",
		clusterName,
		"-o",
		"jsonpath='{.spec.pxc.size}'",
	}
	strSize, err := helpers.RunCmd(args...)
	strSize = strings.Trim(strSize, "'")
	if err != nil {
		return err
	}
	clusterSize, err = strconv.Atoi(strSize)
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
		"--type=merge",
		`--patch={"spec":{"pxc":{"image":"percona/percona-xtradb-cluster-operator:1.4.0-pxc8.0-debug"}}}`,
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
		helpers.RunCmd(args...)
	}
	return nil
}

func CheckPodStatus(podID int) (bool, error) {
	args := []string{
		"get",
		"pod", clusterName + "-pxc-" + strconv.Itoa(podID),
		"-o",
		"jsonpath='{.status.containerStatuses[0].ready}'",
	}
	output, err := helpers.RunCmd(args...)
	if err != nil {
		return false, err
	}
	if strings.Trim(output, "'") == "true" {
		return true, nil
	}
	return false, nil
}

func PodZeroReady() error {
	podZeroStatus := false
	var err error
	for podZeroStatus != true {
		time.Sleep(time.Second * 10)
		podZeroStatus, err = CheckPodStatus(0)
		if err != nil {
			return err
		}
	}
	return nil
}

func CheckPodPhase(podID int, phase string) (bool, error) {
	args := []string{
		"get",
		"pod", clusterName + "-pxc-" + strconv.Itoa(podID),
		"-o",
		"jsonpath='{.status.phase}'",
	}
	output, err := helpers.RunCmd(args...)
	if err != nil {
		return false, err
	}
	if strings.Trim(output, "'") == phase {
		return true, nil
	}
	return false, nil
}

func AllPodsRunning() error {
	for i := 0; i < clusterSize; i++ {
		running := false
		for running == false {
			time.Sleep(time.Second * 10)
			running, _ = CheckPodPhase(i, "Running")
		}
	}
	return nil
}

func RunCommandInPod(podID int, cmd ...string) (string, error) {
	args := []string{
		"exec",
		clusterName + "-pxc-" + strconv.Itoa(podID),
		"--",
	}
	args = append(args, cmd...)
	output, err := helpers.RunCmd(args...)
	if err != nil {
		return "", err
	}
	return output, nil
}

func SetSSTInProgress() error {
	for i := 0; i < clusterSize; i++ {
		_, err := RunCommandInPod(i, "touch", "/var/lib/mysql/sst_in_progress")
		if err != nil {
			return err
		}
	}
	return nil
}

func AllPodsReady() error {
	for i := 0; i < clusterSize; i++ {
		podReadyStatus := false
		var err error
		for podReadyStatus == false {
			time.Sleep(time.Second * 10)
			podReadyStatus, err = CheckPodStatus(i)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func FindMostRecentPod() error {
	var podID int
	seqNo := 0
	for i := 0; i < clusterSize; i++ {
		output, err := RunCommandInPod(i, "cat", "/var/lib/mysql/grastate.dat")
		if err != nil {
			return err
		}
		re := regexp.MustCompile(`(?m)seqno:\s*(\d*)`)
		match := re.FindSubmatch([]byte(output))
		currentSeqNo, err := strconv.Atoi(string(match[1]))
		if err != nil {
			return err
		}
		if currentSeqNo > seqNo {
			seqNo = currentSeqNo
			podID = i
		}
	}
	mostRecentPod = podID
	fmt.Println(mostRecentPod)
	return nil
}
