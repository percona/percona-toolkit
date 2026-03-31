package dumper

import (
	"archive/tar"
	"context"
	"fmt"
	"io"
	"path"
	"strings"

	log "github.com/sirupsen/logrus"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// getContainerEnvMap parses environment variables from pod container spec once
func (d *Dumper) getContainerEnvMap(ctx context.Context, namespace, podName, containerName string) (map[string]string, error) {
	pod, err := d.clientSet.CoreV1().Pods(namespace).Get(ctx, podName, metav1.GetOptions{})
	if err != nil {
		return nil, err
	}

	envMap := make(map[string]string)
	for _, c := range pod.Spec.Containers {
		if c.Name == containerName {
			for _, e := range c.Env {
				envMap[e.Name] = e.Value
			}
			return envMap, nil
		}
	}

	return nil, fmt.Errorf("container %s not found in pod %s/%s", containerName, namespace, podName)
}

// replaceEnvVars replaces environment variables in input using provided env map
func replaceEnvVars(input string, envMap map[string]string) string {
	result := input
	for envName, envValue := range envMap {
		result = strings.ReplaceAll(result, "$"+envName, envValue)
	}
	return result
}

func (d *Dumper) getIndividualFiles(ctx context.Context, job exportJob, crType string) {
	normalizedCRType := resourceType(crType)

	for _, indf := range d.individualFiles {
		if resourceType(indf.resourceName) != normalizedCRType {
			continue
		}

		// Parse environment variables once for this container
		envMap, err := d.getContainerEnvMap(ctx, job.Pod.Namespace, job.Pod.Name, indf.containerName)
		if err != nil {
			log.Warnf("Failed to get env for container %q: %v", indf.containerName, err)
			continue
		}

		// Process individual files
		for _, indPath := range indf.filepaths {
			resolvedPath := replaceEnvVars(indPath, envMap)
			if err := d.processSingleFile(ctx, job, indf.containerName, "", resolvedPath); err != nil {
				log.Warnf("Failed to process file %q: %v", resolvedPath, err)
			}
		}

		// Process directories
		for tarFolder, dirPaths := range indf.dirpaths {
			for _, dirPath := range dirPaths {
				resolvedPath := replaceEnvVars(dirPath, envMap)
				if err := d.processDir(ctx, job, indf.containerName, tarFolder, resolvedPath); err != nil {
					log.Warnf("Skipping directory %q: %v", resolvedPath, err)
				}
			}
		}
	}
}

func (d *Dumper) processSingleFile(
	ctx context.Context,
	job exportJob,
	container, tarFolder, filePath string,
) error {

	tr, rc, stderr, err := d.tarFromPod(ctx, job.Pod, container, filePath)
	if err != nil {
		return fmt.Errorf("exec tar: %w (stderr: %s)", err, stderr.String())
	}
	defer rc.Close()

	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		if hdr.Typeflag != tar.TypeReg {
			continue
		}

		if path.Base(hdr.Name) != path.Base(filePath) {
			continue
		}

		dst := d.PodIndividualFilesPath(
			job.Pod.Namespace,
			job.Pod.Name,
			path.Join(tarFolder, path.Base(filePath)),
		)

		return d.archive.WriteFile(dst, tr, hdr.Size)
	}

	return fmt.Errorf("file %q not found", filePath)
}

func (d *Dumper) processDir(
	ctx context.Context,
	job exportJob,
	container, tarFolder, dir string,
) error {

	tr, rc, _, err := d.tarFromPod(ctx, job.Pod, container, "-C", dir, ".")
	if err != nil {
		return err
	}
	defer rc.Close()

	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}

		if hdr.Typeflag != tar.TypeReg {
			continue
		}

		dst := d.PodIndividualFilesPath(
			job.Pod.Namespace,
			job.Pod.Name,
			path.Join(tarFolder, path.Base(hdr.Name)),
		)

		if err := d.archive.WriteFile(dst, tr, hdr.Size); err != nil {
			return err
		}
	}
}
