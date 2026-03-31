package utils

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	clientcmdapi "k8s.io/client-go/tools/clientcmd/api"
)

func WaitForAllStatefulSetReady(ctx context.Context, client kubernetes.Interface, namespace string) error {
	return wait.PollUntilContextCancel(ctx, 15*time.Second, true, func(ctx context.Context) (bool, error) {
		stsList, err := client.AppsV1().StatefulSets(namespace).List(ctx, metav1.ListOptions{})
		if err != nil {
			if strings.Contains(err.Error(), "connection refused") {
				log.Printf("Got connection refused: %s, retrying...", err.Error())
				return false, nil
			}
			return false, err
		}

		if len(stsList.Items) == 0 {
			return false, nil
		}

		allReady := true
		for _, sts := range stsList.Items {
			desired := int32(1)
			if sts.Spec.Replicas != nil {
				desired = *sts.Spec.Replicas
			}

			ready := sts.Status.ReadyReplicas
			log.Printf("Checking STS %q: %d/%d ready", sts.Name, ready, desired)

			if ready < desired {
				allReady = false
			}
		}

		return allReady, nil
	})
}

func WaitForAllPodsReady(
	ctx context.Context,
	client kubernetes.Interface,
	namespace string,
) error {
	log.Printf("Waiting for all pods to be Ready. Delete all pods that are Failed form the cluster")
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

		for _, pod := range pods.Items {
			if pod.Status.Phase == corev1.PodSucceeded {
				continue
			}

			log.Printf("Waiting for pod %s: Phase=%s, Ready=false", pod.Name, pod.Status.Phase)

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

func GetNamespaces(ctx context.Context, client kubernetes.Interface) ([]string, error) {
	nsList, err := client.CoreV1().Namespaces().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}

	var namespaces []string
	for _, ns := range nsList.Items {
		namespaces = append(namespaces, ns.Name)
	}

	return namespaces, nil
}

func isPodReady(pod *corev1.Pod) bool {
	for _, cond := range pod.Status.ContainerStatuses {
		if !cond.Ready {
			return false
		}
	}
	return true
}

// MergeKubeconfig merges kubeconfig text into ~/.kube/config using client-go
func MergeKubeconfig(newCfgText string) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get home dir: %w", err)
	}

	kubeDir := filepath.Join(homeDir, ".kube")
	if err := os.MkdirAll(kubeDir, 0755); err != nil {
		return fmt.Errorf("failed to create .kube dir: %w", err)
	}

	mainCfgPath := filepath.Join(kubeDir, "config")

	newCfg, err := clientcmd.Load([]byte(newCfgText))
	if err != nil {
		return fmt.Errorf("failed to parse new kubeconfig: %w", err)
	}

	var mainCfg *clientcmdapi.Config
	if _, err := os.Stat(mainCfgPath); err == nil {
		mainCfg, err = clientcmd.LoadFromFile(mainCfgPath)
		if err != nil {
			return fmt.Errorf("failed to load existing kubeconfig: %w", err)
		}
	} else {
		mainCfg = clientcmdapi.NewConfig()
	}

	for name, cluster := range newCfg.Clusters {
		mainCfg.Clusters[name] = cluster
	}
	for name, authInfo := range newCfg.AuthInfos {
		mainCfg.AuthInfos[name] = authInfo
	}
	for name, context := range newCfg.Contexts {
		mainCfg.Contexts[name] = context
	}
	if newCfg.CurrentContext != "" {
		mainCfg.CurrentContext = newCfg.CurrentContext
	}

	if err := clientcmd.WriteToFile(*mainCfg, mainCfgPath); err != nil {
		return fmt.Errorf("failed to write merged kubeconfig: %w", err)
	}

	return nil
}
