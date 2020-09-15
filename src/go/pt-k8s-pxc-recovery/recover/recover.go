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
	MostRecentPod int
	Namespace     string
	ClusterImage  string
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
		return fmt.Errorf("error getting cluster size, %v", err)
	}
	return nil
}

func (c *Cluster) GetClusterImage() error {
	args := []string{
		"get",
		"pod",
		c.Name + "-pxc-0",
		"-o",
		"jsonpath='{.spec.containers[0].image}'",
	}
	clusterImage, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return err
	}
	c.ClusterImage = strings.Trim(clusterImage, "'")
	return nil
}

func (c *Cluster) getPods() ([]string, error) {
	args := []string{
		"get",
		"pods",
	}
	out, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return []string{}, err
	}
	formatedOutput := strings.Split(out, "\n")
	podNames := []string{}
	for _, v := range formatedOutput {
		podName := strings.Split(v, " ")[0]
		if strings.Contains(podName, c.Name) && strings.Contains(podName, "pxc") {
			podNames = append(podNames, podName)
		}
	}
	return podNames, nil
}

func (c *Cluster) ConfirmCrashedStatus() error {
	podNames, err := c.getPods()
	if err != nil {
		return err
	}
	failedNodes := 0
	for _, pod := range podNames {
		logs, err := kubectl.RunCmd(c.Namespace, "logs", pod)
		if err != nil {
			return fmt.Errorf("error confirming crashed cluster status %s", err.Error())
		}
		if strings.Contains(logs, "grastate.dat") && strings.Contains(logs, "safe_to_bootstrap") {
			failedNodes++
		}
	}
	if len(podNames) != failedNodes {
		return fmt.Errorf("found more than one pod running, can't use recovery tool, please restart failed pods manually")
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
	return err
}

func (c *Cluster) RestartPods() error {
	for i := 0; i < c.Size; i++ {
		args := []string{
			"delete",
			"pod",
			c.Name + "-pxc-" + strconv.Itoa(i),
			"--force",
			"--grace-period=0",
		}
		_, err := kubectl.RunCmd(c.Namespace, args...)
		if err != nil && !strings.Contains(err.Error(), "pods") && !strings.Contains(err.Error(), "not found") {
			return err
		}
	}
	return nil
}

func (c *Cluster) CheckPodReady(podID int) (bool, error) {
	args := []string{
		"get",
		"pod", c.Name + "-pxc-" + strconv.Itoa(podID),
		"-o",
		"jsonpath='{.status.containerStatuses[0].ready}'",
	}
	output, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return false, err
	}
	return strings.Trim(output, "'") == "true", nil
}

func (c *Cluster) PodZeroReady() error {
	podZeroStatus := false
	var err error
	for !podZeroStatus {
		time.Sleep(time.Second * 10)
		podZeroStatus, err = c.CheckPodReady(0)
		if err != nil {
			return err
		}
	}
	return nil
}

func (c *Cluster) CheckPodPhase(podID int, phase string) (bool, error) {
	args := []string{
		"get",
		"pod", c.Name + "-pxc-" + strconv.Itoa(podID),
		"-o",
		"jsonpath='{.status.phase}'",
	}
	output, err := kubectl.RunCmd(c.Namespace, args...)
	if err != nil {
		return false, err
	}
	return strings.Trim(output, "'") == phase, nil
}

func (c *Cluster) AllPodsRunning() error {
	for i := 0; i < c.Size; i++ {
		running := false
		var err error
		for !running {
			time.Sleep(time.Second * 10)
			running, err = c.CheckPodPhase(i, "Running")
			if err != nil && !strings.Contains(err.Error(), "NotFound") {
				return err
			}
		}
	}
	return nil
}

func (c *Cluster) RunCommandInPod(podID int, cmd ...string) (string, error) {
	args := []string{
		"exec",
		c.Name + "-pxc-" + strconv.Itoa(podID),
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
	for i := 0; i < c.Size; i++ {
		_, err := c.RunCommandInPod(i, "touch", "/var/lib/mysql/sst_in_progress")
		if err != nil {
			return err
		}
	}
	return nil
}

func (c *Cluster) AllPodsReady() error {
	for i := 0; i < c.Size; i++ {
		podReadyStatus := false
		var err error
		for !podReadyStatus {
			time.Sleep(time.Second * 10)
			podReadyStatus, err = c.CheckPodReady(i)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func (c *Cluster) FindMostRecentPod() error {
	var podID int
	seqNo := 0
	re := regexp.MustCompile(`(?m)seqno:\s*(\d*)`)
	for i := 0; i < c.Size; i++ {
		output, err := c.RunCommandInPod(i, "cat", "/var/lib/mysql/grastate.dat")
		if err != nil {
			return err
		}
		match := re.FindStringSubmatch(output)
		if len(match) < 2 {
			return fmt.Errorf("unable to get seqno")
		}
		currentSeqNo, err := strconv.Atoi(string(match[1]))
		if err != nil {
			return err
		}
		if currentSeqNo > seqNo {
			seqNo = currentSeqNo
			podID = i
		}
	}
	c.MostRecentPod = podID
	return nil
}

func (c *Cluster) RecoverMostRecentPod() error {
	_, err := c.RunCommandInPod(c.MostRecentPod, "mysqld", "--wsrep_recover")
	if err != nil {
		return err
	}
	_, err = c.RunCommandInPod(c.MostRecentPod, "bash", "-c", "sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/mysql/grastate.dat")
	if err != nil {
		return err
	}
	_, err = c.RunCommandInPod(c.MostRecentPod, "bash", "-c", "sed -i 's/wsrep_cluster_address=.*/wsrep_cluster_address=gcomm:\\/\\//g' /etc/mysql/node.cnf")
	if err != nil {
		return err
	}
	_, err = c.RunCommandInPod(c.MostRecentPod, "mysqld")
	if err != nil {
		return err
	}
	return nil
}

func (c *Cluster) RestartAllPodsExceptMostRecent() error {
	for i := 0; i < c.Size; i++ {
		if i != c.MostRecentPod {
			args := []string{
				"delete",
				"pod",
				c.Name + "-pxc-" + strconv.Itoa(i),
				"--force",
				"--grace-period=0",
			}
			_, err := kubectl.RunCmd(c.Namespace, args...)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func (c *Cluster) RestartMostRecentPod() error {
	args := []string{
		"delete",
		"pod",
		c.Name + "-pxc-" + strconv.Itoa(c.MostRecentPod),
		"--force",
		"--grace-period=0",
	}
	_, err := kubectl.RunCmd(c.Namespace, args...)
	return err
}
