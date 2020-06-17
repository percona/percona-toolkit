package dumper

import (
	"bytes"
	"encoding/json"
	"errors"
	"log"
	"os"
	"os/exec"

	corev1 "k8s.io/api/core/v1"
)

// Dumper struct is for dumping cluster
type Dumper struct {
	cmd       string
	resources []string
	location  string
	Errors    map[string]string
}

// New return new Dumper object
func New(location string) Dumper {
	directory := "cluster-dump"
	if len(location) > 0 {
		directory = location + "/cluster-dump"
	}
	return Dumper{
		cmd: "kubectl",
		resources: []string{
			"pods",
			"replicasets",
			"deployments",
			"daemonsets",
			"replicationcontrollers",
			"events",
		},
		location: directory,
		Errors:   make(map[string]string),
	}
}

type k8sPods struct {
	Items []corev1.Pod `json:"items"`
}

type namespaces struct {
	Items []corev1.Namespace `json:"items"`
}

// DumpCluster create dump of a cluster in Dumper.location
func (d *Dumper) DumpCluster() error {
	output, err := d.runCmd("get", "namespaces", "-o", "json")
	if err != nil {
		return err
	}
	var nss namespaces
	err = json.Unmarshal(output, &nss)
	if err != nil {
		return err
	}

	for _, ns := range nss.Items {
		err = os.MkdirAll(d.location+"/"+ns.Name, 0755)
		if err != nil {
			return err
		}

		output, err = d.runCmd("get", "pods", "-o", "json", "--namespace", ns.Name)
		if err != nil {
			continue // runCmd already stored this error in Dumper.Errors
		}
		var pods k8sPods
		err = json.Unmarshal(output, &pods)
		if err != nil {
			return err
		}

		for _, pod := range pods.Items {
			output, err = d.runCmd("logs", pod.Name, "--namespace", ns.Name, "--all-containers")
			if err != nil {
				continue // runCmd already stored this error in Dumper.Errors
			}
			err = os.MkdirAll(d.location+"/"+ns.Name+"/"+pod.Name, 0755)
			if err != nil {
				return err
			}

			f, err := os.Create(d.location + "/" + ns.Name + "/" + pod.Name + "/logs.txt")
			if err != nil {
				return err
			}
			_, err = f.Write(output)
			if err != nil {
				return err
			}

		}

		for _, resource := range d.resources {
			err = d.getAndWriteToFile(resource, ns.Name)
			if err != nil {
				log.Println(err)
			}
		}
	}

	err = d.getAndWriteToFile("nodes", "")
	if err != nil {
		log.Println(err)
	}

	err = d.writeErrorsToFile()
	if err != nil {
		log.Println(err)
	}

	return nil
}

// runCmd run command (Dumper.cmd) with given args, return it output and save all errors in Dumper.errors
func (d *Dumper) runCmd(args ...string) ([]byte, error) {
	var outb, errb bytes.Buffer
	cmd := exec.Command(d.cmd, args...)
	cmd.Stdout = &outb
	cmd.Stderr = &errb
	err := cmd.Run()
	if err != nil {
		d.saveCommandError(err.Error()+" "+outb.String(), args...)
		return outb.Bytes(), err
	}
	if len(errb.String()) > 0 {
		d.saveCommandError(errb.String()+" "+outb.String(), args...)
		return outb.Bytes(), err
	}

	return outb.Bytes(), nil
}

func (d *Dumper) getAndWriteToFile(name, namespace string) error {
	location := d.location
	args := []string{"get", name, "-o", "yaml"}
	if len(namespace) > 0 {
		args = append(args, "--namespace", namespace)
		location = d.location + "/" + namespace
	}
	output, err := d.runCmd(args...)
	if err != nil {
		return nil // runCmd already stored this error in Dumper.Errors
	}

	f, err := os.Create(location + "/" + name + ".yaml")
	if err != nil {
		return err
	}
	_, err = f.Write(output)
	if err != nil {
		return err
	}

	return nil
}

func (d *Dumper) saveCommandError(err string, args ...string) {
	command := d.cmd
	for _, arg := range args {
		command += " " + arg
	}

	d.Errors[command] = err
}

func (d *Dumper) writeErrorsToFile() error {
	var errStr string
	for cmd, errS := range d.Errors {
		errStr += cmd + ": " + errS + "\n"
	}
	f, err := os.Create(d.location + "/errors.txt")
	if err != nil {
		return err
	}
	_, err = f.WriteString(errStr)
	if err != nil {
		return err
	}

	return nil
}

// DeleteDumpDir delete Dumper.location
func (d *Dumper) DeleteDumpDir() error {
	if d.location == "/" {
		return errors.New("don't do this, please") // just for being sure
	}

	return os.RemoveAll(d.location)
}

// GetLocation return Dumper.location
func (d *Dumper) GetLocation() string {
	return d.location
}
