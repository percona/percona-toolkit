package dumper

import (
	"context"
	"io"
	"os"

	corev1 "k8s.io/api/core/v1"
)

func (d *Dumper) exportPodLogs(ctx context.Context, pod corev1.Pod) error {
	containers := append(pod.Spec.InitContainers, pod.Spec.Containers...)

	for _, c := range containers {
		if err := d.exportContainerLogs(ctx, pod, c.Name); err != nil {
			return err
		}
	}
	return nil
}

func (d *Dumper) exportContainerLogs(
	ctx context.Context,
	pod corev1.Pod,
	container string,
) error {

	logOptions := &corev1.PodLogOptions{Container: container}
	req := d.clientSet.CoreV1().
		Pods(pod.Namespace).
		GetLogs(pod.Name, logOptions)

	stream, err := req.Stream(ctx)
	if err != nil {
		return err
	}
	defer stream.Close()

	tmp, err := os.CreateTemp("", "pod-log-*.log")
	if err != nil {
		return err
	}
	defer func() {
		tmp.Close()
		os.Remove(tmp.Name())
	}()

	if _, err := io.Copy(tmp, stream); err != nil {
		return err
	}

	info, err := tmp.Stat()
	if err != nil {
		return err
	}

	if _, err := tmp.Seek(0, 0); err != nil {
		return err
	}

	path := d.PodLogPath(pod.Namespace, pod.Name, container)
	return d.archive.WriteFile(path, tmp, info.Size())
}
