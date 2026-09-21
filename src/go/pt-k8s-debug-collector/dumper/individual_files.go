package dumper

import (
	"archive/tar"
	"context"
	"fmt"
	"io"
	"path"
	"strings"

	log "github.com/sirupsen/logrus"
	corev1 "k8s.io/api/core/v1"
)

// getContainerEnvMap parses environment variables from pod container spec once
func (d *Dumper) getContainerEnvMap(pod corev1.Pod, containerName string) (map[string]string, error) {
	envMap := make(map[string]string)
	for _, c := range pod.Spec.Containers {
		if c.Name == containerName {
			for _, e := range c.Env {
				envMap[e.Name] = e.Value
			}
			return envMap, nil
		}
	}

	return nil, fmt.Errorf("container %s not found in pod %s/%s", containerName, pod.Namespace, pod.Name)
}

// replaceEnvVars replaces environment variables in input using provided env map
func replaceEnvVars(input string, envMap map[string]string) string {
	result := input
	for envName, envValue := range envMap {
		result = strings.ReplaceAll(result, "$"+envName, envValue)
	}
	return result
}

func selectContainer(pod corev1.Pod, candidates []string) (string, bool) {
	for _, candidate := range candidates {
		for _, c := range pod.Spec.Containers {
			if c.Name == candidate {
				return candidate, true
			}
		}
	}
	return "", false
}

func (d *Dumper) getIndividualFiles(ctx context.Context, job exportJob, crType string) {
	normalizedCRType := resourceType(crType)

	for _, indf := range d.individualFiles {
		if resourceType(indf.resourceName) != normalizedCRType {
			continue
		}

		container, ok := selectContainer(job.Pod, indf.containerNames)
		if !ok {
			log.Warnf("None of the containers %v were found in pod %s/%s, skipping", indf.containerNames, job.Pod.Namespace, job.Pod.Name)
			continue
		}

		// Parse environment variables once for this container
		envMap, err := d.getContainerEnvMap(job.Pod, container)
		if err != nil {
			log.Warnf("Failed to get env for container %q: %v", container, err)
			continue
		}

		// Process individual files
		for _, indPath := range indf.filepaths {
			resolvedPath := replaceEnvVars(indPath, envMap)
			if err := d.processSingleFile(ctx, job, container, "", resolvedPath); err != nil {
				log.Warnf("Failed to process file %q: %v", resolvedPath, err)
			}
		}

		// Process directories
		for tarFolder, dirPaths := range indf.dirpaths {
			for _, dirPath := range dirPaths {
				resolvedPath := replaceEnvVars(dirPath, envMap)
				if err := d.processDir(ctx, job, container, tarFolder, resolvedPath); err != nil {
					log.Warnf("Skipping directory %q: %v", resolvedPath, err)
				}
			}
		}

		for tarFolder, cmds := range indf.toolCmds {
			for _, cmd := range cmds {
				if err := d.processToolOutput(ctx, job, container, tarFolder, cmd); err != nil {
					log.Warnf("Skipping tool cmd %v: %v", cmd.args, err)
				}
			}
		}
	}
}

func (d *Dumper) processToolOutput(
	ctx context.Context,
	job exportJob,
	container, tarFolder string, cmd toolLog,
) error {
	out, stderr, err := d.executeInPod(ctx, cmd.args, job.Pod, container, nil)
	if err != nil {
		return fmt.Errorf("exec %v: %w (stderr: %s)", cmd.args, err, stderr.String())
	}

	dst := d.PodIndividualFilesPath(job.Pod.Namespace, job.Pod.Name, path.Join(tarFolder, cmd.filename))

	return d.archive.WriteVirtualFile(dst, out.Bytes())
}

func (d *Dumper) processSingleFile(
	ctx context.Context,
	job exportJob,
	container, tarFolder, filePath string,
) error {

	tr, rc, err := d.tarFromPod(ctx, job.Pod, container, filePath)
	if err != nil {
		return fmt.Errorf("exec tar: %w", err)
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
			path.Join(tarFolder, path.Clean(strings.TrimPrefix(filePath, "/"))),
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

	tr, rc, err := d.tarFromPod(ctx, job.Pod, container, "-C", dir, ".")
	if err != nil {
		return err
	}
	defer rc.Close()

	baseDir := path.Clean(strings.TrimPrefix(dir, "/"))

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

		// Preserve the relative path from the tar header while ensuring it
		// cannot escape the intended destination directory.
		relPath := path.Clean(hdr.Name)
		// Normalize common tar prefixes like "./"
		relPath = strings.TrimPrefix(relPath, "./")
		// Prevent path traversal outside tarFolder by stripping leading "../"
		for strings.HasPrefix(relPath, "../") {
			relPath = strings.TrimPrefix(relPath, "../")
		}
		// Skip entries that do not resolve to a meaningful relative path
		if relPath == "" || relPath == "." {
			continue
		}

		dst := d.PodIndividualFilesPath(
			job.Pod.Namespace,
			job.Pod.Name,
			path.Join(tarFolder, baseDir, relPath),
		)

		if err := d.archive.WriteFile(dst, tr, hdr.Size); err != nil {
			return err
		}
	}
}
