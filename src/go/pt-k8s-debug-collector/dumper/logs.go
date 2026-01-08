package dumper

import (
	"context"
	"io"
	"os"

	corev1 "k8s.io/api/core/v1"
)

const (
	MaxRamPerLog = 50 * 1024 * 1024 // 50MB RAM limit before spilling to disk
)

func (d *Dumper) exportPodLogs(ctx context.Context, pod corev1.Pod) error {
	containers := append(pod.Spec.InitContainers, pod.Spec.Containers...)

	for _, c := range containers {
		logOptions := &corev1.PodLogOptions{Container: c.Name}
		req := d.clientSet.CoreV1().Pods(pod.Namespace).GetLogs(pod.Name, logOptions)

		stream, err := req.Stream(ctx)
		if err != nil {
			return err
		}

		tmp, err := os.CreateTemp("", "pod-log-*.log")
		if err != nil {
			stream.Close()
			return err
		}
		defer func() {
			tmp.Close()
			os.Remove(tmp.Name())
		}()

		_, err = io.Copy(tmp, stream)
		stream.Close()
		if err != nil {
			return err
		}

		info, err := tmp.Stat()
		if err != nil {
			return err
		}

		if _, err := tmp.Seek(0, 0); err != nil {
			return err
		}

		path := d.PodLogPath(pod.Namespace, pod.Name, c.Name)
		if err := d.archive.WriteFile(path, tmp, info.Size()); err != nil {
			return err
		}

		tmp.Close()
		os.Remove(tmp.Name())
	}

	return nil
}
