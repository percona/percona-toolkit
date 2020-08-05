package dumper

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
)

// Dumper struct is for dumping cluster
type Dumper struct {
	cmd       string
	resources []string
	namespace string
	location  string
	errors    string
	mode      int64
	crType    string
}

// New return new Dumper object
func New(location, namespace, resource string) Dumper {
	resources := []string{
		"pods",
		"replicasets",
		"deployments",
		"statefulsets",
		"replicationcontrollers",
		"events",
		"configmaps",
		"secrets",
		"cronjobs",
		"jobs",
		"podsecuritypolicies",
		"poddisruptionbudgets",
		"perconaxtradbbackups",
		"perconaxtradbclusterbackups",
		"perconaxtradbclusterrestores",
		"perconaxtradbclusters",
		"clusterrolebindings",
		"clusterroles",
		"rolebindings",
		"roles",
		"storageclasses",
		"persistentvolumeclaims",
		"persistentvolumes",
	}
	if len(resource) > 0 {
		resources = append(resources, resource)
	}
	return Dumper{
		cmd:       "kubectl",
		resources: resources,
		location:  "cluster-dump",
		mode:      int64(0777),
		namespace: namespace,
		crType:    resource,
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
	file, err := os.Create(d.location + ".tar.gz")
	if err != nil {
		return errors.Wrap(err, "create tar file")
	}

	zr := gzip.NewWriter(file)
	tw := tar.NewWriter(zr)
	defer func() {
		err = addToArchive(d.location+"/errors.txt", d.mode, []byte(d.errors), tw)
		if err != nil {
			log.Println("Error: add errors.txt to archive:", err)
		}

		err = tw.Close()
		if err != nil {
			log.Println("close tar writer", err)
			return
		}
		err = zr.Close()
		if err != nil {
			log.Println("close gzip writer", err)
			return
		}
		err = file.Close()
		if err != nil {
			log.Println("close file", err)
			return
		}
	}()

	var nss namespaces

	if len(d.namespace) > 0 {
		ns := corev1.Namespace{}
		ns.Name = d.namespace
		nss.Items = append(nss.Items, ns)
	} else {
		args := []string{"get", "namespaces", "-o", "json"}
		output, err := d.runCmd(args...)
		if err != nil {
			d.logError(err.Error(), args...)
			return errors.Wrap(err, "get namespaces")
		}

		err = json.Unmarshal(output, &nss)
		if err != nil {
			d.logError(err.Error(), "unmarshal namespaces")
			return errors.Wrap(err, "unmarshal namespaces")
		}
	}

	for _, ns := range nss.Items {
		args := []string{"get", "pods", "-o", "json", "--namespace", ns.Name}
		output, err := d.runCmd(args...)
		if err != nil {
			d.logError(err.Error(), args...)
			continue
		}

		var pods k8sPods
		err = json.Unmarshal(output, &pods)
		if err != nil {
			d.logError(err.Error(), "unmarshal pods from namespace", ns.Name)
			log.Printf("Error: unmarshal pods in namespace %s: %v", ns.Name, err)
		}

		for _, pod := range pods.Items {
			location := filepath.Join(d.location, ns.Name, pod.Name, "logs.txt")
			args := []string{"logs", pod.Name, "--namespace", ns.Name, "--all-containers"}
			output, err = d.runCmd(args...)
			if err != nil {
				d.logError(err.Error(), args...)
				err = addToArchive(location, d.mode, []byte(err.Error()), tw)
				if err != nil {
					log.Printf("Error: create archive with logs for pod %s in namespace %s: %v", pod.Name, ns.Name, err)
				}
				continue
			}
			err = addToArchive(location, d.mode, output, tw)
			if err != nil {
				d.logError(err.Error(), "create archive for pod "+pod.Name)
				log.Printf("Error: create archive for pod %s: %v", pod.Name, err)
			}
			if len(pod.Labels) == 0 {
				continue
			}
			location = filepath.Join(d.location, ns.Name, pod.Name, "/pt-summary.txt")
			component := d.crType
			if d.crType == "psmdb" {
				component = "mongod"
			}
			if pod.Labels["app.kubernetes.io/component"] == component {
				output, err = d.getPodSummary(d.crType, pod.Name, pod.Labels["app.kubernetes.io/instance"], tw)
				if err != nil {
					d.logError(err.Error(), d.crType, pod.Name)
					err = addToArchive(location, d.mode, []byte(err.Error()), tw)
					if err != nil {
						log.Printf("Error: create pt-summary errors archive for pod %s in namespace %s: %v", pod.Name, ns.Name, err)
					}
					continue
				}
				err = addToArchive(location, d.mode, output, tw)
				if err != nil {
					d.logError(err.Error(), "create pt-summary archive for pod "+pod.Name)
					log.Printf("Error: create pt-summary  archive for pod %s: %v", pod.Name, err)
				}
			}
		}

		for _, resource := range d.resources {
			err = d.getResource(resource, ns.Name, tw)
			if err != nil {
				log.Printf("Error: get %s resource: %v", resource, err)
			}
		}
	}

	err = d.getResource("nodes", "", tw)
	if err != nil {
		return errors.Wrapf(err, "get nodes")
	}

	return nil
}

// runCmd run command (Dumper.cmd) with given args, return it output
func (d *Dumper) runCmd(args ...string) ([]byte, error) {
	var outb, errb bytes.Buffer
	cmd := exec.Command(d.cmd, args...)
	cmd.Stdout = &outb
	cmd.Stderr = &errb
	err := cmd.Run()
	if err != nil || errb.Len() > 0 {
		return nil, errors.Errorf("error: %v, stderr: %s, stdout: %s", err, errb.String(), outb.String())
	}

	return outb.Bytes(), nil
}

func (d *Dumper) getResource(name, namespace string, tw *tar.Writer) error {
	location := d.location
	args := []string{"get", name, "-o", "yaml"}
	if len(namespace) > 0 {
		args = append(args, "--namespace", namespace)
		location = filepath.Join(d.location, namespace)
	}
	location = filepath.Join(location, name+".yaml")
	output, err := d.runCmd(args...)
	if err != nil {
		d.logError(err.Error(), args...)
		log.Printf("Error: get resource %s in namespace %s: %v", name, namespace, err)
		return addToArchive(location, d.mode, []byte(err.Error()), tw)
	}

	return addToArchive(location, d.mode, output, tw)
}

func (d *Dumper) logError(err string, args ...string) {
	d.errors += d.cmd + " " + strings.Join(args, " ") + ": " + err + "\n"
}

func addToArchive(location string, mode int64, content []byte, tw *tar.Writer) error {
	hdr := &tar.Header{
		Name: location,
		Mode: mode,
		Size: int64(len(content)),
	}
	if err := tw.WriteHeader(hdr); err != nil {
		return errors.Wrapf(err, "write header to %s", location)
	}
	if _, err := tw.Write(content); err != nil {
		return errors.Wrapf(err, "write content to %s", location)
	}

	return nil
}

type crSecrets struct {
	Spec struct {
		SecretName string `json:"secretsName,omitempty"`
		Secrets    struct {
			Users string `json:"users,omitempty"`
		} `json:"secrets,omitempty"`
	} `json:"spec"`
}

func (d *Dumper) getPodSummary(resource, podName, crName string, tw *tar.Writer) ([]byte, error) {
	var (
		summCmdName string
		ports       string
		summCmdArgs []string
	)

	switch resource {
	case "pxc":
		cr, err := d.getCR("pxc/" + crName)
		if err != nil {
			return nil, errors.Wrap(err, "get cr")
		}
		pass, err := d.getDataFromSecret(cr.Spec.SecretName, "root")
		if err != nil {
			return nil, errors.Wrap(err, "get password from pxc users secret")
		}
		ports = "3306:3306"
		summCmdName = "pt-mysql-summary"
		summCmdArgs = []string{"--host=127.0.0.1", "--port=3306", "--user=root", "--password=" + string(pass)}
	case "psmdb":
		cr, err := d.getCR("psmdb/" + crName)
		if err != nil {
			return nil, errors.Wrap(err, "get cr")
		}
		pass, err := d.getDataFromSecret(cr.Spec.Secrets.Users, "MONGODB_CLUSTER_ADMIN_PASSWORD")
		if err != nil {
			return nil, errors.Wrap(err, "get password from psmdb users secret")
		}
		ports = "27017:27017"
		summCmdName = "pt-mongodb-summary"
		summCmdArgs = []string{"--username=clusterAdmin", "--password=" + pass, "--authenticationDatabase=admin", "127.0.0.1:27017"}
	}

	cmdPortFwd := exec.Command(d.cmd, "port-forward", "pod/"+podName, ports)
	go func() {
		err := cmdPortFwd.Run()
		if err != nil {
			d.logError(err.Error(), "port-forward")
		}
	}()
	defer func() {
		err := cmdPortFwd.Process.Kill()
		if err != nil {
			d.logError(err.Error(), "kill port-forward")
		}
	}()

	time.Sleep(3 * time.Second) // wait for port-forward command

	var outb, errb bytes.Buffer
	cmd := exec.Command(summCmdName, summCmdArgs...)
	cmd.Stdout = &outb
	cmd.Stderr = &errb
	err := cmd.Run()
	if err != nil {
		return nil, errors.Errorf("error: %v, stderr: %s, stdout: %s", err, errb.String(), outb.String())
	}

	return []byte(fmt.Sprintf("stderr: %s, stdout: %s", errb.String(), outb.String())), nil
}

func (d *Dumper) getCR(crName string) (crSecrets, error) {
	var cr crSecrets
	output, err := d.runCmd("get", crName, "-o", "json")
	if err != nil {
		return cr, errors.Wrap(err, "get "+crName)
	}
	err = json.Unmarshal(output, &cr)
	if err != nil {
		return cr, errors.Wrap(err, "unmarshal psmdb cr")
	}

	return cr, nil
}

func (d *Dumper) getDataFromSecret(secretName, dataName string) (string, error) {
	passEncoded, err := d.runCmd("get", "secrets/"+secretName, "--template={{.data."+dataName+"}}")
	if err != nil {
		return "", errors.Wrap(err, "run get secret cmd")
	}
	pass, err := base64.StdEncoding.DecodeString(string(passEncoded))
	if err != nil {
		return "", errors.Wrap(err, "decode data")
	}

	return string(pass), nil
}
