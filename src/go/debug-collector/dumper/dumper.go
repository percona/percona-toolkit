package dumper

import (
	"bytes"
	"encoding/json"
	"log"
	"os/exec"
	"strings"

	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
)

// Dumper struct is for dumping cluster
type Dumper struct {
	cmd       string
	resources []string
	location  string
	Errors    map[string]string
	Files     map[string][]byte
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
		Files:    make(map[string][]byte),
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
		return errors.Wrap(err, "get namespaces")
	}
	var nss namespaces
	err = json.Unmarshal(output, &nss)
	if err != nil {
		return errors.Wrap(err, "unmarshal namespaces")
	}

	for _, ns := range nss.Items {
		output, err = d.runCmd("get", "pods", "-o", "json", "--namespace", ns.Name)
		if err != nil {
			continue // runCmd already stored this error in Dumper.Errors
		}
		var pods k8sPods
		err = json.Unmarshal(output, &pods)
		if err != nil {
			log.Println(errors.Wrap(err, "unmarshal pods"))
		}

		for _, pod := range pods.Items {
			output, err = d.runCmd("logs", pod.Name, "--namespace", ns.Name, "--all-containers")
			if err != nil {
				continue // runCmd already stored this error in Dumper.Errors
			}
			d.Files[d.location+"/"+ns.Name+"/"+pod.Name+"/logs.txt"] = output
		}

		for _, resource := range d.resources {
			err = d.getResource(resource, ns.Name)
			if err != nil {
				log.Println(errors.Wrapf(err, "get %s resource", resource))
			}
		}
	}

	err = d.getResource("nodes", "")
	if err != nil {
		log.Println(errors.Wrapf(err, "get nodes"))
	}

	err = d.writeErrorsToFile()
	if err != nil {
		log.Println(errors.Wrap(err, "write errors"))
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
	if errb.Len() > 0 {
		d.saveCommandError(errb.String()+" "+outb.String(), args...)
		return outb.Bytes(), err
	}

	return outb.Bytes(), nil
}

func (d *Dumper) getResource(name, namespace string) error {
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

	d.Files[location+"/"+name+".yaml"] = output

	return nil
}

func (d *Dumper) saveCommandError(err string, args ...string) {
	command := d.cmd + " " + strings.Join(args, " ")

	d.Errors[command] = err
}

func (d *Dumper) writeErrorsToFile() error {
	var errStr string
	for cmd, errS := range d.Errors {
		errStr += cmd + ": " + errS + "\n"
	}
	d.Files[d.location+"/errors.txt"] = []byte(errStr)

	return nil
}

// GetLocation return Dumper.location
func (d *Dumper) GetLocation() string {
	return d.location
}
