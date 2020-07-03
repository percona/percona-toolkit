package dumper

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"log"
	"os"
	"os/exec"
	"strings"

	"github.com/pkg/errors"
	corev1 "k8s.io/api/core/v1"
)

// Dumper struct is for dumping cluster
type Dumper struct {
	cmd       string
	resources []string
	namespace string
	location  string
	Errors    string
	mode      int64
}

// New return new Dumper object
func New(location, namespace, resource string) Dumper {
	directory := "cluster-dump"
	if len(location) > 0 {
		directory = location + "/cluster-dump"
	}
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
		location:  directory,
		mode:      int64(0777),
		namespace: namespace,
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
	tarFile, err := os.Create(d.location + ".tar.gz")
	if err != nil {
		return errors.Wrap(err, "create tar file")
	}

	zr := gzip.NewWriter(tarFile)
	tw := tar.NewWriter(zr)
	defer func() {
		err = tw.Close()
		if err != nil {
			log.Panicln("close tar writer", err)
			return
		}
		err = zr.Close()
		if err != nil {
			log.Panicln("close gzip writer", err)
			return
		}
		err = tarFile.Close()
		if err != nil {
			log.Panicln("close tar file", err)
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
			d.saveCommandError(err.Error(), args...)
			return errors.Wrap(err, "get namespaces")
		}

		err = json.Unmarshal(output, &nss)
		if err != nil {
			d.saveCommandError(err.Error(), "unmarshal namespaces")
			return errors.Wrap(err, "unmarshal namespaces")
		}
	}

	for _, ns := range nss.Items {
		args := []string{"get", "pods", "-o", "json", "--namespace", ns.Name}
		output, err := d.runCmd(args...)
		if err != nil {
			d.saveCommandError(err.Error(), args...)
			continue
		}

		var pods k8sPods
		err = json.Unmarshal(output, &pods)
		if err != nil {
			d.saveCommandError(err.Error(), "unmarshal pods from namespace", ns.Name)
			log.Println(errors.Wrap(err, "unmarshal pods"))
		}

		for _, pod := range pods.Items {
			location := d.location + "/" + ns.Name + "/" + pod.Name + "/logs.txt"
			args := []string{"logs", pod.Name, "--namespace", ns.Name, "--all-containers"}
			output, err = d.runCmd(args...)
			if err != nil {
				log.Printf("logs pod %s namespace %s: %v", pod.Name, ns.Name, err)
				d.saveCommandError(err.Error(), args...)
				err = createArchive(location, d.mode, []byte(err.Error()), tw)
				if err != nil {
					log.Printf("create archive with err: %v", err)
				}
				continue
			}
			err = createArchive(location, d.mode, output, tw)
			if err != nil {
				log.Printf("create archive for pod %s: %v", pod.Name, err)
			}
		}

		for _, resource := range d.resources {
			err = d.getResource(resource, ns.Name, tw)
			if err != nil {
				log.Println(errors.Wrapf(err, "get %s resource", resource))
			}
		}

		err = createArchive(d.location+"/errors.txt", d.mode, []byte(d.Errors), tw)
		if err != nil {
			log.Println(errors.Wrap(err, "write errors"))
		}
	}

	err = d.getResource("nodes", "", tw)
	if err != nil {
		log.Println(errors.Wrapf(err, "get nodes"))
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
		return nil, errors.Errorf("error: %v, stderr: %s, stdout: %s", err, errb, outb)
	}

	return outb.Bytes(), nil
}

func (d *Dumper) getResource(name, namespace string, tw *tar.Writer) error {
	location := d.location
	args := []string{"get", name, "-o", "yaml"}
	if len(namespace) > 0 {
		args = append(args, "--namespace", namespace)
		location = d.location + "/" + namespace
	}
	location += "/" + name + ".yaml"
	output, err := d.runCmd(args...)
	if err != nil {
		d.saveCommandError(err.Error(), args...)
		log.Printf("get resource %s namespace %s: %v", name, namespace, err)
		return createArchive(location, d.mode, []byte(err.Error()), tw)
	}

	return createArchive(location, d.mode, output, tw)
}

func (d *Dumper) saveCommandError(err string, args ...string) {
	d.Errors += d.cmd + " " + strings.Join(args, " ") + ": " + err + "\n"
}

func createArchive(location string, mode int64, content []byte, tw *tar.Writer) error {
	hdr := &tar.Header{
		Name: location,
		Mode: mode,
		Size: int64(len(content)),
	}
	if err := tw.WriteHeader(hdr); err != nil {
		return errors.Wrap(err, "write header")
	}
	if _, err := tw.Write(content); err != nil {
		return errors.Wrapf(err, "write content to %s", location)
	}

	return nil
}
