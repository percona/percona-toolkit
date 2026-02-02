package dumper

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func (d *Dumper) getSecretValueFromPod(ctx context.Context, pod corev1.Pod, secretName string) (string, error) {
	for _, volume := range pod.Spec.Volumes {
		if volume.Secret == nil {
			continue
		}

		secret, err := d.clientSet.CoreV1().Secrets(pod.Namespace).Get(ctx, volume.Secret.SecretName, metav1.GetOptions{})
		if err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return "", fmt.Errorf("error fetching secret '%s/%s': %w", pod.Namespace, volume.Secret.SecretName, err)
		}

		secretValueBytes, found := secret.Data[secretName]
		if found {
			return string(secretValueBytes), nil
		}
	}
	return "", fmt.Errorf("could not find any secret with name %s in Pod '%s/%s'", secretName, pod.Namespace, pod.Name)
}
