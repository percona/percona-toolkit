package dumper

import (
	"archive/tar"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log"

	corev1 "k8s.io/api/core/v1"
)

func (d *Dumper) getIndividualFiles(ctx context.Context, job exportJob, crType string) {
	for _, indf := range d.individualFiles {
		if indf.resourceName == crType {
			for _, indPath := range indf.filepaths {
				file, err := d.getFileFromPod(ctx, job.Pod, indPath, indf.containerName)
				if err != nil {
					log.Printf("error while getting individual files for %q pod and %q namespace to dump: %s, SKIPPING", job.Pod.Name, job.Pod.Namespace, err)
					continue
				}

				if len(file) != 0 {
					log.Printf("writing individual file with path %s to dump", indPath)
					path := d.PodIndividualFilesPath(job.Pod.Namespace, job.Pod.Name, indPath)
					err = d.archive.WriteVirtualFile(path, file)
					if err != nil {
						log.Printf("error while writing individual files for %q pod and %q namespace to dump: %s", job.Pod.Name, job.Pod.Namespace, err)
					}
				}
			}
		}
	}
}

func (d *Dumper) getFileFromPod(ctx context.Context, pod corev1.Pod, filepath, containerName string) ([]byte, error) {
	if len(filepath) == 0 || len(containerName) == 0 {
		return nil, errors.New("container name or filepath is not specified")
	}

	cmd := []string{"tar", "cf", "-", filepath}
	stdout, stderr, err := d.executeInPod(ctx, cmd, pod, containerName, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to execute command in Pod: stderr: %s: %w", &stderr, err)
	}

	tarReader := tar.NewReader(&stdout)
	var fileContentBuffer bytes.Buffer
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("error reading tar header: %w", err)
		}

		if header.Typeflag == tar.TypeReg && header.Name == filepath {
			_, copyErr := io.Copy(&fileContentBuffer, tarReader)
			if copyErr != nil {
				return nil, fmt.Errorf("error copying file content: %w", copyErr)
			}
		}
	}

	return fileContentBuffer.Bytes(), nil
}
