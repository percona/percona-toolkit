package utils

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/apimachinery/pkg/util/yaml"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// ClusterConfig describes k3d cluster configuration
type ClusterConfig struct {
	Port        int
	OperatorURL string
	CRURL       string
	Job         string
	ServerSide  bool
}

var CLUSTERS = map[string]ClusterConfig{
	"pxc": {
		Port:        6443,
		OperatorURL: "https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/main/deploy/bundle.yaml",
		CRURL:       "https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/main/deploy/cr.yaml",
		ServerSide:  true,
	},
	"ps": {
		Port:        6444,
		OperatorURL: "https://raw.githubusercontent.com/percona/percona-server-mysql-operator/main/deploy/bundle.yaml",
		CRURL:       "https://raw.githubusercontent.com/percona/percona-server-mysql-operator/main/deploy/cr.yaml",
		ServerSide:  true,
	},
	"psmdb": {
		Port:        6445,
		OperatorURL: "https://raw.githubusercontent.com/percona/percona-server-mongodb-operator/main/deploy/bundle.yaml",
		CRURL:       "https://raw.githubusercontent.com/percona/percona-server-mongodb-operator/main/deploy/cr.yaml",
		ServerSide:  true,
	},
	"pgo": {
		Port:        6446,
		OperatorURL: "https://raw.githubusercontent.com/percona/percona-postgresql-operator/1.x/deploy/operator.yaml",
		CRURL:       "https://raw.githubusercontent.com/percona/percona-postgresql-operator/1.x/deploy/cr.yaml",
		Job:         "pgo-deploy",
	},
	"pgv2": {
		Port:        6447,
		OperatorURL: "https://raw.githubusercontent.com/percona/percona-postgresql-operator/main/deploy/bundle.yaml",
		CRURL:       "https://raw.githubusercontent.com/percona/percona-postgresql-operator/main/deploy/cr.yaml",
		ServerSide:  true,
	},
}

func run(cmd *exec.Cmd, capture bool) (string, error) {
	if capture {
		output, err := cmd.CombinedOutput()
		return strings.TrimSpace(string(output)), err
	}
	return "", cmd.Run()
}

func createCluster(ctx context.Context, name string, port int) error {
	fmt.Printf("creating cluster %s\n", name)

	cmd := exec.CommandContext(ctx, "k3d", "cluster", "create", name,
		"-p", fmt.Sprintf("%d:6443", port),
		"--agents", "2",
		"--network", "k3d-net",
		"--api-port", fmt.Sprintf("127.0.0.1:%d", port),
	)
	if _, err := run(cmd, false); err != nil {
		return fmt.Errorf("failed to create cluster: %w", err)
	}

	return nil
}

func getKubeClient(contextName string) (*kubernetes.Clientset, *dynamic.DynamicClient, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get home dir: %w", err)
	}

	kubeconfigPath := filepath.Join(homeDir, ".kube", "config")

	config, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
		&clientcmd.ClientConfigLoadingRules{ExplicitPath: kubeconfigPath},
		&clientcmd.ConfigOverrides{CurrentContext: contextName},
	).ClientConfig()
	if err != nil {
		return nil, nil, fmt.Errorf("failed to load kubeconfig: %w", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create kubernetes client: %w", err)
	}

	dynamicClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create dynamic client: %w", err)
	}

	return clientset, dynamicClient, nil
}

func waitForJob(ctx context.Context, clientset *kubernetes.Clientset, ns, jobName string, timeout time.Duration) error {
	fmt.Printf("waiting for job %s in namespace %s\n", jobName, ns)

	return wait.PollUntilContextTimeout(ctx, 5*time.Second, timeout, true, func(ctx context.Context) (bool, error) {
		job, err := clientset.BatchV1().Jobs(ns).Get(ctx, jobName, metav1.GetOptions{})
		if err != nil {
			return false, err
		}

		for _, condition := range job.Status.Conditions {
			if condition.Type == batchv1.JobComplete && condition.Status == corev1.ConditionTrue {
				return true, nil
			}
			if condition.Type == batchv1.JobFailed && condition.Status == corev1.ConditionTrue {
				fmt.Printf("job %s failed\n", jobName)
				pods, _ := clientset.CoreV1().Pods(ns).List(ctx, metav1.ListOptions{
					LabelSelector: fmt.Sprintf("job-name=%s", jobName),
				})
				for _, pod := range pods.Items {
					req := clientset.CoreV1().Pods(ns).GetLogs(pod.Name, &corev1.PodLogOptions{})
					logs, _ := req.Stream(ctx)
					if logs != nil {
						io.Copy(os.Stdout, logs)
						logs.Close()
					}
				}
				return false, fmt.Errorf("job %s failed", jobName)
			}
		}

		return false, nil
	})
}

func getGVR(gvk schema.GroupVersionKind) schema.GroupVersionResource {
	// Special cases for known Kubernetes resources
	pluralMap := map[string]string{
		"Endpoints":                      "endpoints",
		"SecurityContextConstraints":     "securitycontextconstraints",
		"CustomResourceDefinition":       "customresourcedefinitions",
		"ClusterRole":                    "clusterroles",
		"ClusterRoleBinding":             "clusterrolebindings",
		"ServiceAccount":                 "serviceaccounts",
		"ConfigMap":                      "configmaps",
		"PodDisruptionBudget":            "poddisruptionbudgets",
		"MutatingWebhookConfiguration":   "mutatingwebhookconfigurations",
		"ValidatingWebhookConfiguration": "validatingwebhookconfigurations",
	}

	resource := strings.ToLower(gvk.Kind)

	if plural, ok := pluralMap[gvk.Kind]; ok {
		resource = plural
	} else {
		resource = resource + "s"
	}

	return schema.GroupVersionResource{
		Group:    gvk.Group,
		Version:  gvk.Version,
		Resource: resource,
	}
}

func waitForCRDReady(ctx context.Context, dynamicClient *dynamic.DynamicClient, crdName string, timeout time.Duration) error {
	gvr := schema.GroupVersionResource{
		Group:    "apiextensions.k8s.io",
		Version:  "v1",
		Resource: "customresourcedefinitions",
	}

	return wait.PollUntilContextTimeout(ctx, 2*time.Second, timeout, true, func(ctx context.Context) (bool, error) {
		crd, err := dynamicClient.Resource(gvr).Get(ctx, crdName, metav1.GetOptions{})
		if err != nil {
			return false, nil
		}

		conditions, found, err := unstructured.NestedSlice(crd.Object, "status", "conditions")
		if err != nil || !found {
			return false, nil
		}

		for _, condition := range conditions {
			condMap, ok := condition.(map[string]interface{})
			if !ok {
				continue
			}
			condType, _, _ := unstructured.NestedString(condMap, "type")
			condStatus, _, _ := unstructured.NestedString(condMap, "status")

			if condType == "Established" && condStatus == "True" {
				return true, nil
			}
		}

		return false, nil
	})
}

func downloadAndApplyYAML(ctx context.Context, dynamicClient *dynamic.DynamicClient, url, namespace string, waitForCRDs bool) error {
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("failed to download YAML: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to download YAML: status %d", resp.StatusCode)
	}

	var objects []unstructured.Unstructured
	decoder := yaml.NewYAMLOrJSONDecoder(resp.Body, 4096)

	for {
		var obj unstructured.Unstructured
		if err := decoder.Decode(&obj); err != nil {
			if err == io.EOF {
				break
			}
			return fmt.Errorf("failed to decode YAML: %w", err)
		}

		if obj.Object == nil {
			continue
		}

		objects = append(objects, obj)
	}

	var crds []unstructured.Unstructured
	var others []unstructured.Unstructured

	for _, obj := range objects {
		if obj.GetKind() == "CustomResourceDefinition" {
			crds = append(crds, obj)
		} else {
			others = append(others, obj)
		}
	}

	for _, obj := range crds {
		if err := applyObject(ctx, dynamicClient, &obj, namespace); err != nil {
			return err
		}
	}

	if waitForCRDs && len(crds) > 0 {
		for _, crd := range crds {
			crdName := crd.GetName()
			fmt.Printf("waiting for CRD %s...\n", crdName)
			if err := waitForCRDReady(ctx, dynamicClient, crdName, 60*time.Second); err != nil {
				return fmt.Errorf("CRD %s not ready: %w", crdName, err)
			}
		}
	}

	for _, obj := range others {
		if err := applyObject(ctx, dynamicClient, &obj, namespace); err != nil {
			return err
		}
	}

	return nil
}

func applyObject(ctx context.Context, dynamicClient *dynamic.DynamicClient, obj *unstructured.Unstructured, namespace string) error {
	if obj.GetNamespace() == "" && obj.GetKind() != "Namespace" && obj.GetKind() != "ClusterRole" &&
		obj.GetKind() != "ClusterRoleBinding" && obj.GetKind() != "CustomResourceDefinition" &&
		obj.GetKind() != "MutatingWebhookConfiguration" && obj.GetKind() != "ValidatingWebhookConfiguration" {
		obj.SetNamespace(namespace)
	}

	gvk := obj.GroupVersionKind()
	gvr := getGVR(gvk)

	var err error
	var isNamespaced = obj.GetNamespace() != ""

	if isNamespaced {
		_, err = dynamicClient.Resource(gvr).Namespace(obj.GetNamespace()).
			Create(ctx, obj, metav1.CreateOptions{})
	} else {
		_, err = dynamicClient.Resource(gvr).
			Create(ctx, obj, metav1.CreateOptions{})
	}

	if err != nil {
		if strings.Contains(err.Error(), "already exists") {
			if isNamespaced {
				_, err = dynamicClient.Resource(gvr).Namespace(obj.GetNamespace()).
					Update(ctx, obj, metav1.UpdateOptions{})
			} else {
				_, err = dynamicClient.Resource(gvr).
					Update(ctx, obj, metav1.UpdateOptions{})
			}
		}
		if err != nil && !strings.Contains(err.Error(), "already exists") {
			return fmt.Errorf("failed to apply %s/%s: %w", gvk.Kind, obj.GetName(), err)
		}
	}

	return nil
}

func waitForDeployments(ctx context.Context, clientset *kubernetes.Clientset, namespace string, timeout time.Duration) error {
	deployments, err := clientset.AppsV1().Deployments(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("failed to list deployments: %w", err)
	}

	for _, deploy := range deployments.Items {
		fmt.Printf("waiting for deployment %s...\n", deploy.Name)

		err := wait.PollUntilContextTimeout(ctx, 2*time.Second, timeout, true, func(ctx context.Context) (bool, error) {
			d, err := clientset.AppsV1().Deployments(namespace).Get(ctx, deploy.Name, metav1.GetOptions{})
			if err != nil {
				return false, err
			}

			if d.Status.ReadyReplicas == *d.Spec.Replicas && d.Status.ReadyReplicas > 0 {
				return true, nil
			}
			return false, nil
		})

		if err != nil {
			return fmt.Errorf("deployment %s not ready: %w", deploy.Name, err)
		}
	}

	return nil
}

// DeployK3d deploys specified k3d clusters with Percona operators
func DeployK3d(ctx context.Context, name string) (string, error) {
	cfg, ok := CLUSTERS[name]
	if !ok {
		return "", fmt.Errorf("invalid deployment: %s", name)
	}

	_ = exec.CommandContext(ctx, "k3d", "cluster", "delete", name).Run()

	fmt.Printf("deploying cluster: %s\n", name)

	if err := createCluster(ctx, name, cfg.Port); err != nil {
		return "", fmt.Errorf("failed to create cluster %s: %w", name, err)
	}

	cmd := exec.CommandContext(ctx, "k3d", "kubeconfig", "get", name)
	cfgBytes, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to get kubeconfig content: %w", err)
	}

	configText := string(cfgBytes)

	clientset, dynamicClient, err := GetKubeClientFromRaw(configText, "k3d-"+name)
	if err != nil {
		return configText, err
	}

	ns := &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
		},
	}
	_, err = clientset.CoreV1().Namespaces().Create(ctx, ns, metav1.CreateOptions{})
	if err != nil && !strings.Contains(err.Error(), "already exists") {
		return "", fmt.Errorf("failed to create namespace: %w", err)
	}

	fmt.Printf("deploying operator %s\n", name)
	if err := downloadAndApplyYAML(ctx, dynamicClient, cfg.OperatorURL, name, true); err != nil {
		return "", fmt.Errorf("failed to deploy operator %s: %w", name, err)
	}

	if err := waitForDeployments(ctx, clientset, name, 240*time.Second); err != nil {
		return "", fmt.Errorf("failed to wait for deployments: %w", err)
	}

	if cfg.Job != "" {
		if err := waitForJob(ctx, clientset, name, cfg.Job, 10*time.Minute); err != nil {
			return "", fmt.Errorf("failed to wait for jobs: %w", err)
		}
	}

	err = wait.PollUntilContextTimeout(ctx, 5*time.Second, 120*time.Second, true, func(ctx context.Context) (bool, error) {
		err := downloadAndApplyYAML(ctx, dynamicClient, cfg.CRURL, name, false)
		if err != nil {
			if strings.Contains(err.Error(), "could not find the requested resource") {
				fmt.Printf("CRD not ready yet, retrying...\n")
				return false, nil
			}
			return false, err
		}
		return true, nil
	})
	if err != nil {
		return "", fmt.Errorf("failed to deploy CR %s: %w", name, err)
	}

	return configText, nil
}

// DestroyK3d destroys k3d clusters. If no deployments specified, destroys all known clusters
func DestroyK3d(ctx context.Context, deployments ...string) error {
	toDestroy := deployments
	if len(toDestroy) == 0 {
		for name := range CLUSTERS {
			toDestroy = append(toDestroy, name)
		}
	}

	for _, name := range toDestroy {
		fmt.Printf("deleting cluster %s...\n", name)
		cmd := exec.CommandContext(ctx, "k3d", "cluster", "delete", name)
		if _, err := run(cmd, false); err != nil {
			fmt.Printf("warning: failed to delete cluster %s: %v\n", name, err)
		}
	}

	return nil
}

func GetKubeClientFromRaw(rawConfig string, contextName string) (*kubernetes.Clientset, *dynamic.DynamicClient, error) {
	clientConfig, err := clientcmd.NewClientConfigFromBytes([]byte(rawConfig))
	if err != nil {
		return nil, nil, err
	}

	rawCfg, err := clientConfig.RawConfig()
	if err != nil {
		return nil, nil, err
	}
	rawCfg.CurrentContext = contextName

	config, err := clientcmd.NewDefaultClientConfig(rawCfg, &clientcmd.ConfigOverrides{}).ClientConfig()
	if err != nil {
		return nil, nil, err
	}

	cs, err := kubernetes.NewForConfig(config)
	dc, err := dynamic.NewForConfig(config)
	return cs, dc, err
}
