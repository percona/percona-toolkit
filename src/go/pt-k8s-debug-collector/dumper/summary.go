package dumper

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os/exec"

	corev1 "k8s.io/api/core/v1"
)

func (d *Dumper) getSummary(ctx context.Context, job exportJob, crType string, location string) {
	if !d.skipPodSummary {
		output, err := d.getPodSummary(ctx, job.Pod, crType)
		if err != nil {
			log.Printf("error while creating summary for %q pod and %q namespace: %s", job.Pod.Name, job.Pod.Namespace, err)
			err = d.archive.WriteVirtualFile(location, []byte(err.Error()))
			if err != nil {
				log.Printf("Error: create summary errors archive for pod %s in namespace %s: %v", job.Pod.Name, job.Pod.Namespace, err)
			}
		} else {
			log.Printf("Created summary for pod/namespace %q/%q, Writing to dump", job.Pod.Name, job.Pod.Namespace)
			err = d.archive.WriteVirtualFile(location, output)
			if err != nil {
				log.Printf("error while writing summary for %q pod and %q namespace to dump: %s", job.Pod.Name, job.Pod.Namespace, err)
			}
		}
	}
}

func (d *Dumper) getPodSummary(ctx context.Context, pod corev1.Pod, crName string) ([]byte, error) {
	var (
		summCmdName string
		summCmdArgs []string
	)

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	switch crName {
	case "pxc", "ps":
		var port string
		if d.forwardport != "" {
			port = d.forwardport
		} else {
			port = ""
		}

		pass, err := d.getSecretValueFromPod(ctx, pod, "root")
		if err != nil {
			return nil, fmt.Errorf("failed to get password from pxc/ps users secret: %w", err)
		}

		localport, err := d.portForwardPod(ctx, pod, port, "3306")
		if err != nil {
			if !errors.Is(err, ERR_PORT_ALREADY_FORWARDED) {
				return nil, err
			}
		}

		summCmdName = "pt-mysql-summary"
		summCmdArgs = []string{"--host=127.0.0.1", "--port=" + fmt.Sprintf("%d", localport), "--user=root", "--password=" + pass}

	case "pgv2", "pg":
		scriptURL := "https://raw.githubusercontent.com/percona/support-snippets/master/postgresql/pg_gather/gather.sql"
		resp, err := http.Get(scriptURL)
		if err != nil {
			return nil, fmt.Errorf("error fetching SQL script: %w", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("failed to fetch SQL script, status code: %d", resp.StatusCode)
		}
		command := []string{"psql", "-X", "-f", "-"}

		outb, errb, err := d.executeInPod(ctx, command, pod, "database", resp.Body)
		if err != nil {
			return nil, fmt.Errorf("failed to execute command inside pod stdout: %s\n, stderr: %s: %w", outb.String(), errb.String(), err)
		}
		return outb.Bytes(), nil

	case "psmdb":
		var port string
		if d.forwardport != "" {
			port = d.forwardport
		} else {
			port = ""
		}

		user, err := d.getSecretValueFromPod(ctx, pod, "MONGODB_DATABASE_ADMIN_USER")
		if err != nil {
			return nil, fmt.Errorf("get user name from psmdb users secret: %w", err)
		}
		pass, err := d.getSecretValueFromPod(ctx, pod, "MONGODB_DATABASE_ADMIN_PASSWORD")
		if err != nil {
			return nil, fmt.Errorf("get password from psmdb users secret: %w", err)
		}

		localport, err := d.portForwardPod(ctx, pod, port, "27017")
		if err != nil {
			if !errors.Is(err, ERR_PORT_ALREADY_FORWARDED) {
				return nil, err
			}
		}

		summCmdName = "pt-mongodb-summary"
		summCmdArgs = []string{"--username=" + user, "--password=" + string(pass), "--authenticationDatabase=admin", "127.0.0.1:" + fmt.Sprintf("%d", localport)}
	}

	var outb, errb bytes.Buffer
	cmd := exec.Command(summCmdName, summCmdArgs...)
	cmd.Stdout = &outb
	cmd.Stderr = &errb
	err := cmd.Run()
	if err != nil {
		return nil, fmt.Errorf("stderr: %s\nstdout: %s \nerr: %w", errb.String(), outb.String(), err)
	}
	return outb.Bytes(), nil
}
