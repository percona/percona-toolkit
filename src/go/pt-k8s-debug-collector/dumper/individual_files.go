package dumper

import (
	"archive/tar"
	"context"
	"fmt"
	"io"
	"log"
	"path"
)

func (d *Dumper) getIndividualFiles(ctx context.Context, job exportJob, crType string) {
	for _, indf := range d.dumpFiles {
		if indf.resourceName != crType {
			continue
		}

		var err error
		for _, indPath := range indf.filepaths {
			indPath, err = d.ParseEnvsFromSpec(ctx, job.Pod.Namespace, job.Pod.Name, indf.containerName, indPath)
			if err != nil {
				log.Printf("Skipping dump file %q. Failed to parse ENV's", indPath)
				continue
			}
			if err := d.processSingleFile(ctx, job, indf.containerName, "", indPath); err != nil {
				log.Printf("Skipping dump file %q: %v", indPath, err)
			}
		}

		for tarFolder, dirPaths := range indf.dirpaths {
			for _, dirPath := range dirPaths {
				dirPath, err = d.ParseEnvsFromSpec(ctx, job.Pod.Namespace, job.Pod.Name, indf.containerName, dirPath)
				if err != nil {
					log.Printf("Skipping dump directory %q. Failed to parse ENV's", dirPath)
					continue
				}

				if err := d.processDir(ctx, job, indf.containerName, tarFolder, dirPath); err != nil {
					log.Printf("Skipping dump directory %q: %v", dirPath, err)
				}
			}
		}

		for tarFolder, cmds := range indf.toolCmds {
			for _, cmd := range cmds {
				if err := d.processToolOutput(ctx, job, indf.containerName, tarFolder, cmd); err != nil {
					log.Printf("Skipping dump cmd %s: %v", cmd, err)
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
		return fmt.Errorf("exec %s: %w (stderr: %s)", cmd, err, stderr.String())
	}

	dst := d.PodIndividualFilesPath(job.Pod.Namespace, job.Pod.Name, path.Join(tarFolder, cmd.filename))

	return d.archive.WriteVirtualFile(dst, out.Bytes())
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
