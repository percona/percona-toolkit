package dumper

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os/exec"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var TargetSSLKeys = []string{"tls.crt", "ca.crt", "tls-ca.crt", "root.crt"}

func (d *Dumper) dumpSSLInfo(ctx context.Context, namespace string) error {
	secretList, err := d.clientSet.CoreV1().Secrets(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("failed to get secrets: %w", err)
	}

	for _, secret := range secretList.Items {
		secretName := secret.GetName()
		if secret.Type == corev1.SecretTypeTLS || secret.Type == corev1.SecretTypeOpaque {
			result, err := decodeCertToBytes(secret)
			if err != nil {
				log.Printf("error decoding cert %s: %v", secretName, err)
			}

			if len(result) != 0 {
				path := d.NamespaceIndividualFilesPath(namespace, secretName)
				if err := d.archive.WriteVirtualFile(path, result); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

func decodeCertToBytes(secret corev1.Secret) ([]byte, error) {
	var result []byte

	for _, key := range TargetSSLKeys {
		certData, ok := secret.Data[key]
		if !ok {
			continue
		}

		if len(certData) == 0 {
			continue
		}

		cmd := exec.Command("openssl", "x509", "-noout", "-text")
		cmd.Stdin = bytes.NewReader(certData)

		var outb, errb bytes.Buffer
		cmd.Stdout = &outb
		cmd.Stderr = &errb

		err := cmd.Run()
		if err != nil {
			errMsg := fmt.Sprintf("ERROR running openssl on key %s: %v\nStderr: %s\n", key, err, errb.String())
			result = append(result, []byte(errMsg)...)
		} else {
			header := fmt.Sprintf("\n--- Decoded %s ---\n", key)
			result = append(result, []byte(header)...)
			result = append(result, outb.Bytes()...)
		}
	}

	return result, nil
}

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
