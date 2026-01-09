package utils

import (
	"context"
	"log"
	"time"

	"github.com/goforj/godump"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
)

func WaitForAllStatefulSetReady(ctx context.Context, client kubernetes.Interface, namespace string) error {
	return wait.PollUntilContextCancel(ctx, 15*time.Second, true, func(ctx context.Context) (bool, error) {
		stsList, err := client.AppsV1().StatefulSets(namespace).List(ctx, metav1.ListOptions{})
		if err != nil {
			return false, err
		}

		desiredNum := len(stsList.Items)

		for _, stsItem := range stsList.Items {
			log.Printf("Waiting for StatefulSet: %q", stsItem.Name)

			sts, err := client.AppsV1().StatefulSets(namespace).Get(ctx, stsItem.Name, metav1.GetOptions{})
			if err != nil {
				return false, err
			}

			desired := int32(1)
			if sts.Spec.Replicas != nil {
				desired = *sts.Spec.Replicas
			}

			ready := sts.Status.ReadyReplicas

			log.Printf("StatefulSet %q: \n%s", stsItem.Name, godump.DumpStr(sts.Status))

			log.Printf("StatefulSet %q: desired=%d ready=%d\n", stsItem.Name, desired, ready)

			if ready == desired {
				desiredNum--
			}
		}

		if desiredNum <= 0 {
			return true, nil
		}

		return false, nil
	})
}

func WaitForAllPodsReady(
	ctx context.Context,
	client kubernetes.Interface,
	namespace string,
) error {
	return wait.PollUntilContextCancel(ctx, 15*time.Second, true, func(ctx context.Context) (bool, error) {
		pods, err := client.CoreV1().
			Pods(namespace).
			List(ctx, metav1.ListOptions{})
		if err != nil {
			return false, err
		}

		if len(pods.Items) == 0 {
			return false, nil
		}

		for i, pod := range pods.Items {
			if pod.Status.Phase != corev1.PodSucceeded {
				continue
			}

			log.Printf("%dPOD:\n%s", i, godump.DumpStr(pod))

			if pod.Status.Phase != corev1.PodRunning {
				return false, nil
			}

			if !isPodReady(&pod) {
				return false, nil
			}
		}

		return true, nil
	})
}

func isPodReady(pod *corev1.Pod) bool {
	for _, cond := range pod.Status.ContainerStatuses {
		if !cond.Ready {
			return false
		}
	}
	return true
}
