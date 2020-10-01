package recover

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/percona/percona-toolkit/src/go/pt-k8s-pxc-recovery/kubectl"
)

type Cluster struct {
	Name          string
	Size          int
	MostRecentPod string
	Namespace     string
}

func (c *Cluster) SetClusterSize() error {
	args := []string{
		"get",
		"pxc",
		c.Name,
		"-o",
		"jsonpath='{.spec.pxc.size}'",
	}
	strSize, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return err
	}
	strSize = strings.Trim(strSize, "'")
	c.Size, err = strconv.Atoi(strSize)
	if err != nil {
		return fmt.Errorf("error getting cluster size, %s", err)
	}
	return nil
}

func (c *Cluster) GetClusterImage() (string, error) {
	args := []string{
		"get",
		"pod",
		c.Name + "-pxc-0",
		"-o",
		"jsonpath='{.spec.containers[0].image}'",
	}
	clusterImage, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return "", fmt.Errorf("Error getting cluster image %s", err)
	}
	clusterImage = strings.Trim(clusterImage, "'")
	return clusterImage, nil
}

func (c *Cluster) getPods() ([]string, error) {
	args := []string{
		"get",
		"pods",
		"--no-headers",
		"-o",
		"custom-columns=:metadata.name",
	}
	out, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return []string{}, err
	}
	formatedOutput := strings.Split(out, "\n")
	podNames := []string{}
	for _, podName := range formatedOutput {
		if strings.Contains(podName, c.Name) && strings.Contains(podName, "pxc") {
			podNames = append(podNames, podName)
		}
	}
	return podNames, nil
}

func (c *Cluster) ConfirmCrashedStatus() error {
	podNames, err := c.getPods()
	if err != nil {
		return fmt.Errorf("Error getting pods : %s", err)
	}
	for _, pod := range podNames {
		logs, err := kubectl.RunCmd(c.Namespace, "logs", pod)
		if err != nil {
			return fmt.Errorf("error confirming crashed cluster status %s", err)
		}
		if !strings.Contains(logs, "grastate.dat") && !strings.Contains(logs, "safe_to_bootstrap") &&
			!strings.Contains(logs, "It may not be safe to bootstrap the cluster from this node") {
			return fmt.Errorf("found one or more pods in healthy state, can't use recovery tool, please restart failed pods manually")
		}
	}
	return nil
}

func (c *Cluster) PatchClusterImage(image string) error {
	args := []string{
		"patch",
		"pxc",
		c.Name,
		"--type=merge",
		`--patch={"spec":{"pxc":{"image":"` + image + `"}}}`,
	}
	_, err := kubectl.RunCmd(c.Namespace, args...)
	return fmt.Errorf("error patching cluster image: %s", err)
}

func (c *Cluster) RestartPods() error {
	podNames, err := c.getPods()
	if err != nil {
		return fmt.Errorf("error getting pods to restart pods: %s", err)
	}
	for _, podName := range podNames {
		args := []string{
			"delete",
			"pod",
			podName,
			"--force",
			"--grace-period=0",
		}
		_, err := kubectl.RunCmd(c.Namespace, args...)
		if err != nil && !strings.Contains(err.Error(), "pods") && !strings.Contains(err.Error(), "not found") {
			return fmt.Errorf("error restarting pods: %s", err)
		}
	}
	return nil
}

func (c *Cluster) CheckPodReady(podName string) (bool, error) {
	args := []string{
		"get",
		"pod",
		podName,
		"-o",
		"jsonpath='{.status.containerStatuses[0].ready}'",
	}
	output, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return false, fmt.Errorf("error checking pod ready: %s", err)
	}
	return strings.Trim(output, "'") == "true", nil
}

func (c *Cluster) PodZeroReady() error {
	podNames, err := c.getPods()
	if err != nil {
		return err
	}
	podZeroStatus := false
	for !podZeroStatus {
		time.Sleep(time.Second * 10)
		podZeroStatus, err = c.CheckPodReady(podNames[0])
		if err != nil {
			return err
		}
	}
	return nil
}

func (c *Cluster) CheckPodPhase(podName string, phase string) (bool, error) {
	args := []string{
		"get",
		"pod",
		podName,
		"-o",
		"jsonpath='{.status.phase}'",
	}
	output, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return false, fmt.Errorf("error checking pod phase: %s", err)
	}
	return strings.Trim(output, "'") == phase, nil
}

func (c *Cluster) AllPodsRunning() error {
	podNames, err := c.getPods()
	if err != nil {
		return err
	}
	for _, podName := range podNames {
		running := false
		var err error
		for !running {
			time.Sleep(time.Second * 10)
			running, err = c.CheckPodPhase(podName, "Running")
			if err != nil && !strings.Contains(err.Error(), "NotFound") {
				return err
			}
		}
	}
	return nil
}

func (c *Cluster) RunCommandInPod(podName string, cmd ...string) (string, error) {
	args := []string{
		"exec",
		podName,
		"--",
	}
	args = append(args, cmd...)
	output, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return "", err
	}
	return output, nil
}

func (c *Cluster) SetSSTInProgress() error {
	podNames, err := c.getPods()
	if err != nil {
		return err
	}
	for _, podName := range podNames {
		_, err := c.RunCommandInPod(podName, "touch", "/var/lib/mysql/sst_in_progress")
		if err != nil {
			return fmt.Errorf("error setting sst in progress", err)
		}
	}
	return nil
}

func (c *Cluster) AllPodsReady() error {
	podNames, err := c.getPods()
	if err != nil {
		return err
	}
	for _, podName := range podNames {
		podReadyStatus := false
		for !podReadyStatus {
			time.Sleep(time.Second * 10)
			podReadyStatus, err = c.CheckPodReady(podName)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func (c *Cluster) FindMostRecentPod() error {
	podNames, err := c.getPods()
	if err != nil {
		return err
	}
	var recentPodName string
	seqNo := 0
	re := regexp.MustCompile(`(?m)seqno:\s*(\d*)`)
	for _, podName := range podNames {
		output, err := c.RunCommandInPod(podName, "cat", "/var/lib/mysql/grastate.dat")
		if err != nil {
			return err
		}
		match := re.FindStringSubmatch(output)
		if len(match) < 2 {
			return fmt.Errorf("error finding the most recent pod : unable to get seqno")
		}
		currentSeqNo, err := strconv.Atoi(string(match[1]))
		if err != nil {
			return err
		}
		if currentSeqNo > seqNo {
			seqNo = currentSeqNo
			recentPodName = podName
		}
	}
	c.MostRecentPod = recentPodName
	return nil
}

func (c *Cluster) RecoverMostRecentPod() error {
	_, err := c.RunCommandInPod(c.MostRecentPod, "mysqld", "--wsrep_recover")
	if err != nil {
		return fmt.Errorf("error recovering most recent pod: %s", err)
	}
	_, err = c.RunCommandInPod(c.MostRecentPod, "bash", "-c", "sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/mysql/grastate.dat")
	if err != nil {
		return fmt.Errorf("error recovering most recent pod: %s", err)
	}
	_, err = c.RunCommandInPod(c.MostRecentPod, "bash", "-c", "sed -i 's/wsrep_cluster_address=.*/wsrep_cluster_address=gcomm:\\/\\//g' /etc/mysql/node.cnf")
	if err != nil {
		return fmt.Errorf("error recovering most recent pod: %s", err)
	}
	_, err = c.RunCommandInPod(c.MostRecentPod, "mysqld")
	if err != nil {
		return fmt.Errorf("error recovering most recent pod: %s", err)
	}
	return nil
}

func (c *Cluster) RestartAllPodsExceptMostRecent() error {
	podNames, err := c.getPods()
	if err != nil {
		return err
	}
	for _, podName := range podNames {
		if podName != c.MostRecentPod {
			args := []string{
				"delete",
				"pod",
				podName,
				"--force",
				"--grace-period=0",
			}
			_, err := kubectl.RunCmd(c.Namespace, args...)
			if err != nil {
				return fmt.Errorf("error restarting pods : %s", err)
			}
		}
	}
	return nil
}

func (c *Cluster) RestartMostRecentPod() error {
	args := []string{
		"delete",
		"pod",
		c.MostRecentPod,
		"--force",
		"--grace-period=0",
	}
	_, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return fmt.Errorf("error restarting most recent pod : %s", err)
	}
	return nil
}
