// This program is copyright 2020-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package dumper

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	log "github.com/sirupsen/logrus"

	"go.yaml.in/yaml/v2"
	"golang.org/x/sync/semaphore"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

const (
	defaultConcurrentExportWorkers = 16
)

// Dumper struct is for dumping cluster
type Dumper struct {
	kubeconfig                       string
	namespace                        string
	location                         string
	logger                           *SafeLogger
	mode                             int64
	crTypes                          []string
	forwardport                      string
	usedPorts                        sync.Map
	skipPodSummary                   bool
	concurrentExportWorkers          int
	concurrentExportWorkersCluster   int
	concurrentExportWorkersNamespace int

	sslSecrets      map[string]bool
	individualFiles []individualFile
	clientSet       *kubernetes.Clientset
	dynamicClient   *dynamic.DynamicClient
	discoveryClient *discovery.DiscoveryClient
	archive         *tarWriter
	restConfig      *rest.Config
}

// individualFile struct is used to dump the necessary files from the containers
type individualFile struct {
	resourceName  string
	containerName string
	filepaths     []string
	dirpaths      map[string][]string // map[tarFolder][]dirPaths
}

// resourceMap struct is used to dump the resources from namespace scope or cluster scope
type resourceMap struct {
	ClusterScoped   []schema.GroupVersionResource
	NamespaceScoped []schema.GroupVersionResource
}

// exportJob struct is used in goroutines to access pods
type exportJob struct {
	Pod corev1.Pod
}

// New return new Dumper object
func New(location, namespace, kubeconfig, clusterName, forwardport, resource string, skipPodSummary bool, concurrentExportWorkers int) (*Dumper, error) {
	safeLog := NewSafeLogger()

	log.AddHook(&ErrorArchiveHook{safeLogger: safeLog})

	if clusterName == "" {
		_,  clusterName = parseResourceSpec(resource)
	}

	config, err := buildRestConfig(kubeconfig, clusterName)
	if err != nil {
		return nil, fmt.Errorf("failed to build config from flags: %w", err)
	}

	// Validate and set concurrency level
	if concurrentExportWorkers <= 0 {
		concurrentExportWorkers = defaultConcurrentExportWorkers
	}

	if concurrentExportWorkers > 20 {
		log.Warnf("concurrentExportWorkers value of %d may overwhelm the Kubernetes API server. Consider using a value of 20 or less.", concurrentExportWorkers)
	}

	config.QPS = float32(concurrentExportWorkers) + 1
	config.Burst = (concurrentExportWorkers + 1) * 2

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to parse kubeconfig: %w", err)
	}

	dynclient, err := dynamic.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to parse dynamic kubeconfig: %w", err)
	}

	discclient := discovery.NewDiscoveryClientForConfigOrDie(config)

	d := &Dumper{
		kubeconfig:                       kubeconfig,
		location:                         location,
		mode:                             int64(0o777),
		namespace:                        namespace,
		forwardport:                      strings.TrimSpace(forwardport),
		skipPodSummary:                   skipPodSummary,
		concurrentExportWorkers:          concurrentExportWorkers,
		concurrentExportWorkersCluster:   concurrentExportWorkers / 2,
		concurrentExportWorkersNamespace: concurrentExportWorkers / 2,
		clientSet:                        clientset,
		dynamicClient:                    dynclient,
		discoveryClient:                  discclient,
		restConfig:                       config,
		usedPorts:                        sync.Map{},
		logger:                           safeLog,
	}

	if resource == "none" || resource == "" {
		return d, nil
	}

	d.crTypes, err = d.autoCustomResource()
	if err != nil {
		return nil, err
	}

	d.sslSecrets = make(map[string]bool, 0)
	for _, cr := range d.crTypes {
		switch resourceType(cr) {
		case "pg":
			err := d.addPg1()
			if err != nil {
				return nil, err
			}
		case "pgv2":
			err := d.addPg2()
			if err != nil {
				return nil, err
			}
		case "pxc":
			err := d.addPxc()
			if err != nil {
				return nil, err
			}
		case "ps":
			err := d.addPs()
			if err != nil {
				return nil, err
			}
		case "psmdb":
			err := d.addPsmdb()
			if err != nil {
				return nil, err
			}
		}
	}

	return d, err
}

func buildRestConfig(kubeconfig, clusterName string) (*rest.Config, error) {
	if clusterName == "" {
		return clientcmd.BuildConfigFromFlags("", kubeconfig)
	}

	loadingRules := &clientcmd.ClientConfigLoadingRules{ExplicitPath: kubeconfig}
	overrides := &clientcmd.ConfigOverrides{CurrentContext: clusterName}
	clientConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, overrides)

	rawConfig, err := clientConfig.RawConfig()
	if err != nil {
		return nil, err
	}

	if _, ok := rawConfig.Contexts[clusterName]; !ok {
		return nil, fmt.Errorf("context %q not found in kubeconfig", clusterName)
	}

	return clientConfig.ClientConfig()
}

// DumpCluster create dump of a cluster in Dumper.location
func (d *Dumper) DumpCluster() error {
	var err error
	d.archive, err = NewTarWriter(d.location + ".tar.gz")
	if err != nil {
		return fmt.Errorf("failed to create archive: %v", err)
	}
	defer d.archive.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	defer d.logger.DumpToArchive(d.archive, d.DumperLogPath("errors"))

	log.Info("initializing pod cache")
	factory := informers.NewSharedInformerFactory(d.clientSet, 10*time.Minute)
	podInformer := factory.Core().V1().Pods().Informer()
	factory.Start(ctx.Done())

	log.Info("discovering and exporting API resources")
	if err := d.export(ctx); err != nil {
		return fmt.Errorf("error during resource export: %v", err)
	}

	log.Info("starting workers for pod logs/files...")
	jobsChannel := make(chan exportJob, 100)
	var wg sync.WaitGroup

	for i := range d.concurrentExportWorkers {
		id := i
		wg.Go(func() {
			d.resilientWorker(id, ctx, cancel, jobsChannel)
		})
	}

	log.Info("waiting for pod cache to fully sync...")
	if !cache.WaitForCacheSync(ctx.Done(), podInformer.HasSynced) {
		return fmt.Errorf("timed out waiting for caches to sync.")
	}

	podLister := factory.Core().V1().Pods().Lister()
	allPods, err := podLister.List(labels.Everything())
	if err != nil {
		return fmt.Errorf("failed to list all pods: %v", err)
	}

	log.Infof("dispatching %d pods to workers...", len(allPods))
	for _, pod := range allPods {
		jobsChannel <- exportJob{Pod: *pod}
	}

	close(jobsChannel)
	wg.Wait()

	log.Infof("export complete\ndata saved to %s", d.location)
	return nil
}

func (d *Dumper) export(ctx context.Context) error {
	resources, err := d.discoverResources()
	if err != nil {
		return err
	}

	var wg sync.WaitGroup
	semCluster := semaphore.NewWeighted(int64(d.concurrentExportWorkersCluster))

	for _, gvr := range resources.ClusterScoped {
		wg.Add(1)
		go func(r schema.GroupVersionResource) {
			defer wg.Done()

			if err := semCluster.Acquire(ctx, 1); err != nil {
				log.Errorf("semaphore acquire failed: %s", err)
				return
			}
			defer semCluster.Release(1)

			err := d.exportGeneric(ctx, r, "")
			if err != nil {
				log.Errorf("failed to export resource %q: %s", r.Resource, err)
				return
			}
		}(gvr)
	}

	namespaces, err := d.clientSet.CoreV1().Namespaces().List(ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	semNS := semaphore.NewWeighted(int64(d.concurrentExportWorkersNamespace))

	for _, ns := range namespaces.Items {
		if d.namespace != "" && d.namespace != ns.Name {
			continue
		}

		wg.Add(1)
		go func(namespace string) {
			defer wg.Done()

			if err := semNS.Acquire(ctx, 1); err != nil {
				log.Printf("semaphore acquire failed: %s", err)
				return
			}
			defer semNS.Release(1)

			if err := d.dumpSSLInfo(ctx, namespace); err != nil {
				log.Printf("error dumping secrets for namespace %q: %s", namespace, err)
			}
		}(ns.Name)

		for _, gvr := range resources.NamespaceScoped {
			// Do not collect secrets
			if gvr.Resource == "secrets" {
				continue
			}

			wg.Add(1)
			go func(namespace string, gvr schema.GroupVersionResource) {
				defer wg.Done()

				if err := semNS.Acquire(ctx, 1); err != nil {
					log.Errorf("semaphore acquire failed: %s", err)
					return
				}
				defer semNS.Release(1)

				err := d.exportGeneric(ctx, gvr, namespace)
				if err != nil {
					log.Errorf("failed to export resource %q for namespace %q: %s", gvr.Resource, namespace, err)
					return
				}
			}(ns.Name, gvr)
		}
	}

	wg.Wait()
	return nil
}

func (d *Dumper) exportGeneric(ctx context.Context, gvr schema.GroupVersionResource, ns string) error {
	var intf dynamic.ResourceInterface
	if ns == "" {
		intf = d.dynamicClient.Resource(gvr)
	} else {
		intf = d.dynamicClient.Resource(gvr).Namespace(ns)
	}

	list, err := intf.List(ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	if len(list.Items) == 0 {
		return nil
	}

	for i := range list.Items {
		obj := list.Items[i].Object
		if meta, ok := obj["metadata"].(map[string]any); ok {
			delete(meta, "managedFields")
			delete(meta, "resourceVersion")
			delete(meta, "uid")
			delete(meta, "selfLink")
			delete(meta, "creationTimestamp")
		}
		redactPgbouncerVolumeRefs(obj)
	}

	data, err := yaml.Marshal(list.UnstructuredContent())
	if err != nil {
		return err
	}

	yamlPath := d.PodResourcePath(ns, gvr.Resource)
	d.archive.WriteVirtualFile(yamlPath, data)

	return nil
}

// redactPgbouncerVolumeRefs removes volume and volumeMount entries that reference
// pgbouncer secrets from a pod or pod template spec.
func redactPgbouncerVolumeRefs(obj map[string]any) {
	redactPodSpec(obj)

	// Handle pod templates (Deployment, StatefulSet, etc.)
	if spec, ok := obj["spec"].(map[string]any); ok {
		if tmpl, ok := spec["template"].(map[string]any); ok {
			redactPodSpec(tmpl)
		}
	}
}

func redactPodSpec(obj map[string]any) {
	spec, ok := obj["spec"].(map[string]any)
	if !ok {
		return
	}

	volumes, ok := spec["volumes"].([]any)
	if !ok {
		return
	}

	pgbouncerVols := make(map[string]bool)
	kept := make([]any, 0)
	for _, v := range volumes {
		vol, ok := v.(map[string]any)
		if !ok {
			kept = append(kept, v)
			continue
		}
		if hasPgbouncerSecretRef(vol) {
			name, _ := vol["name"].(string)
			pgbouncerVols[name] = true
		} else {
			kept = append(kept, v)
		}
	}

	if len(pgbouncerVols) == 0 {
		return
	}
	spec["volumes"] = kept

	for _, key := range []string{"containers", "initContainers", "ephemeralContainers"} {
		containers, ok := spec[key].([]any)
		if !ok {
			continue
		}
		for j, c := range containers {
			container, ok := c.(map[string]any)
			if !ok {
				continue
			}
			mounts, ok := container["volumeMounts"].([]any)
			if !ok {
				continue
			}
			var keptMounts []any
			for _, m := range mounts {
				mount, ok := m.(map[string]any)
				if !ok {
					keptMounts = append(keptMounts, m)
					continue
				}
				mountName, _ := mount["name"].(string)
				if !pgbouncerVols[mountName] {
					keptMounts = append(keptMounts, mount)
				}
			}
			container["volumeMounts"] = keptMounts
			containers[j] = container
		}
	}
}

func hasPgbouncerSecretRef(vol map[string]any) bool {
	if secret, ok := vol["secret"].(map[string]any); ok {
		name, _ := secret["secretName"].(string)
		if strings.Contains(name, "pgbouncer") {
			return true
		}
	}
	if projected, ok := vol["projected"].(map[string]any); ok {
		if sources, ok := projected["sources"].([]any); ok {
			for _, s := range sources {
				src, ok := s.(map[string]any)
				if !ok {
					continue
				}
				if secret, ok := src["secret"].(map[string]any); ok {
					name, _ := secret["name"].(string)
					if strings.Contains(name, "pgbouncer") {
						return true
					}
				}
			}
		}
	}
	return false
}

var ignoredResources = map[string]bool{
	"apiaccesses":               true, // Deprecated
	"componentstatuses":         true, // Deprecated
	"endpoints":                 true, // Deprecated
	"subjectaccessreviews":      true, // Not allowed
	"selfsubjectrulesreviews":   true, // Not allowed
	"selfsubjectaccessreviews":  true, // Not allowed
	"selfsubjectreviews":        true, // Not allowed
	"localsubjectaccessreviews": true, // Not allowed
	"bindings":                  true, // Not allowed
	"tokenreviews":              true, // Not allowed
}

func filterResource(resourceName string) bool {
	if strings.Contains(resourceName, "/") {
		return false
	}

	if ignoredResources[resourceName] {
		return false
	}

	return true
}

func (d *Dumper) discoverResources() (*resourceMap, error) {
	lists, err := d.discoveryClient.ServerPreferredResources()
	if err != nil {
		return nil, err
	}
	rm := &resourceMap{}

	chosenGroups := make(map[string]string)

	// Extract groups with priority.
	// If resource exists in legacy (v1) group and in events.k8s.io group
	// events.k8s.io will be chosen
	for _, list := range lists {
		for _, resource := range list.APIResources {
			if !filterResource(resource.Name) {
				continue
			}

			currentGroupVersion := list.GroupVersion
			gv, _ := schema.ParseGroupVersion(currentGroupVersion)
			currentGroup := gv.Group

			existingGroupVersion, found := chosenGroups[resource.Name]
			if !found {
				chosenGroups[resource.Name] = currentGroupVersion
				continue
			}

			egv, _ := schema.ParseGroupVersion(existingGroupVersion)
			if currentGroup == "events.k8s.io" && egv.Group != "events.k8s.io" {
				chosenGroups[resource.Name] = currentGroupVersion
			}
		}
	}

	for _, list := range lists {
		gv, _ := schema.ParseGroupVersion(list.GroupVersion)
		for _, resource := range list.APIResources {
			if !filterResource(resource.Name) {
				continue
			}

			if chosenGroups[resource.Name] != list.GroupVersion {
				continue
			}

			gvr := schema.GroupVersionResource{
				Group:    gv.Group,
				Version:  gv.Version,
				Resource: resource.Name,
			}

			if resource.Namespaced {
				rm.NamespaceScoped = append(rm.NamespaceScoped, gvr)
			} else {
				rm.ClusterScoped = append(rm.ClusterScoped, gvr)
			}
		}
	}
	return rm, nil
}

func (d *Dumper) resilientWorker(id int, ctx context.Context, cancel context.CancelFunc, jobs <-chan exportJob) {
	for {
		select {
		case <-ctx.Done():
			return
		case job, ok := <-jobs:
			if !ok {
				return
			}

			err := d.exportPodLogs(ctx, job.Pod)
			if err != nil {
				if isSpaceError(err) {
					log.Infof("worker %d stopping app: %v", id, err)
					cancel()
					return
				}
				log.Errorf("error exporting logs: %v", err)
			}

			d.getPodDescribe(job.Pod)

			if job.Pod.Status.Phase == corev1.PodRunning {
				d.exportPodSummaryAndFiles(ctx, job)
			}
		}
	}
}

var crLabelMap = map[string]string{
	"psmdb": "mongod",
	"ps":    "mysql",
}

func matchesCR(cr string, podLabels map[string]string) bool {
	if mapped, ok := crLabelMap[cr]; ok {
		cr = mapped
	}

	if podLabels["app.kubernetes.io/component"] == cr ||
		podLabels["app.kubernetes.io/name"] == cr {
		return true
	}

	switch cr {
	case "pg", "pgo":
		return podLabels["pgo-pg-database"] == "true"
	case "pgv2":
		return podLabels["pgv2.percona.com/version"] != "" &&
			podLabels["postgres-operator.crunchydata.com/instance"] != ""
	}

	return false
}

func (d *Dumper) exportPodSummaryAndFiles(ctx context.Context, job exportJob) {
	for _, cr := range d.crTypes {
		normalizedCR := resourceType(cr)

		if !matchesCR(normalizedCR, job.Pod.Labels) {
			continue
		}

		if !d.skipPodSummary {
			d.getSummary(ctx, job, normalizedCR, d.PodSummaryPath(job.Pod.Namespace, job.Pod.Name))
		}

		d.getIndividualFiles(ctx, job, normalizedCR)
	}
}

func isSpaceError(err error) bool {
	return strings.Contains(err.Error(), "no space left on device")
}
