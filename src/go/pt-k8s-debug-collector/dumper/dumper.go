package dumper

import (
	"context"
	"fmt"
	"io"
	"log"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"go.yaml.in/yaml/v2"
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
	NumWorkers = 10 // Concurrency for Pod Logs
)

// Dumper struct is for dumping cluster
type Dumper struct {
	kubeconfig     string
	namespace      string
	location       string
	logger         *SafeLogger
	mode           int64
	crTypes        []string
	forwardport    string
	usedPorts      sync.Map
	skipPodSummary bool

	sslSecrets      map[string]bool
	dumpFiles       []dumpFile
	clientSet       *kubernetes.Clientset
	dynamicClient   *dynamic.DynamicClient
	discoveryClient *discovery.DiscoveryClient
	archive         *tarWriter
	restConfig      *rest.Config
}

type toolLog struct {
	filename string
	args     []string
}

// dumpFile struct is used to dump the necessary files from the pod, or files by executing tool command inside pod
type dumpFile struct {
	resourceName  string
	containerName string
	filepaths     []string
	dirpaths      map[string][]string
	toolCmds      map[string][]toolLog
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
func New(location, namespace, kubeconfig, forwardport, resource string, skipPodSummary bool) (*Dumper, error) {
	var (
		err    error
		config *rest.Config
	)

	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("recovered from panic: %s", r)
		}
	}()

	config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return nil, fmt.Errorf("failed to build config from flags: %w", err)
	}

	config.QPS = 10
	config.Burst = 20

	clientset := kubernetes.NewForConfigOrDie(config)
	dynclient := dynamic.NewForConfigOrDie(config)
	discclient := discovery.NewDiscoveryClientForConfigOrDie(config)

	// TODO: implement cluster name flag
	d := &Dumper{
		kubeconfig:      kubeconfig,
		location:        location,
		mode:            int64(0o777),
		namespace:       namespace,
		forwardport:     forwardport,
		skipPodSummary:  skipPodSummary,
		clientSet:       clientset,
		dynamicClient:   dynclient,
		discoveryClient: discclient,
		restConfig:      config,
		logger:          NewSafeLogger(),
		usedPorts:       sync.Map{},
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

// DumpCluster create dump of a cluster in Dumper.location
func (d *Dumper) DumpCluster() error {
	var err error
	d.archive, err = NewTarWriter(d.location + ".tar.gz")
	if err != nil {
		return fmt.Errorf("Failed to create archive: %v", err)
	}
	defer d.archive.Close()

	oldLoggerOut := log.Writer()
	log.SetOutput(io.MultiWriter(log.Writer(), d.logger))
	defer log.SetOutput(oldLoggerOut)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	defer d.logger.DumpToArchive(d.archive, d.DumperLogPath("dumper"))

	log.Println("Initializing Pod Cache")
	factory := informers.NewSharedInformerFactory(d.clientSet, 10*time.Minute)
	podInformer := factory.Core().V1().Pods().Informer()
	factory.Start(ctx.Done())

	log.Println("Discovering and Exporting API Resources")
	if err := d.export(ctx); err != nil {
		log.Printf("Error during resource export: %v", err)
	}

	log.Println("Starting Workers for Pod Logs/Files...")
	jobsChannel := make(chan exportJob, 100)
	var wg sync.WaitGroup

	for i := range NumWorkers {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			d.resilientWorker(id, ctx, cancel, jobsChannel)
		}(i)
	}

	log.Println("Waiting for Pod Cache to fully sync...")
	if !cache.WaitForCacheSync(ctx.Done(), podInformer.HasSynced) {
		return fmt.Errorf("Timed out waiting for caches to sync.")
	}

	podLister := factory.Core().V1().Pods().Lister()
	allPods, err := podLister.List(labels.Everything())
	if err != nil {
		return fmt.Errorf("Failed to list all pods: %v", err)
	}

	log.Printf("Dispatching %d pods to workers...", len(allPods))
	for _, pod := range allPods {
		jobsChannel <- exportJob{Pod: *pod}
	}

	close(jobsChannel)
	wg.Wait()

	log.Printf("Export Complete. Data saved to %s", d.location)
	return nil
}

func (d *Dumper) export(ctx context.Context) error {
	resources, err := d.discoverResources()
	if err != nil {
		return err
	}

	var wg sync.WaitGroup
	semCluster := make(chan struct{}, 5)

	for _, gvr := range resources.ClusterScoped {
		wg.Add(1)
		go func(r schema.GroupVersionResource) {
			defer wg.Done()
			semCluster <- struct{}{}
			defer func() { <-semCluster }()

			err := d.exportGeneric(ctx, r, "")
			if err != nil {
				log.Printf("failed to export resource %q: %s", r.Resource, err)
				return
			}
		}(gvr)
	}

	namespaces, err := d.clientSet.CoreV1().Namespaces().List(ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}

	semNS := make(chan struct{}, 5)

	for _, ns := range namespaces.Items {
		if d.namespace != "" && d.namespace != ns.Name {
			continue
		}
		wg.Add(1)
		go func(namespace string) {
			defer wg.Done()
			semNS <- struct{}{}
			defer func() { <-semNS }()

			if err := d.dumpSecrets(ctx, namespace); err != nil {
				log.Printf("Error dumping secrets for %s: %v", namespace, err)
			}

			for _, gvr := range resources.NamespaceScoped {
				if gvr.Resource == "secrets" {
					continue
				}
				d.exportGeneric(ctx, gvr, namespace)
			}
		}(ns.Name)
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
	if err != nil || len(list.Items) == 0 {
		return err
	}

	for i := range list.Items {
		obj := list.Items[i].Object
		if meta, ok := obj["metadata"].(map[string]interface{}); ok {
			delete(meta, "managedFields")
			delete(meta, "resourceVersion")
			delete(meta, "uid")
			delete(meta, "selfLink")
			delete(meta, "creationTimestamp")
		}
	}

	data, err := yaml.Marshal(list.UnstructuredContent())
	if err != nil {
		return err
	}

	yamlPath := d.PodResourcePath(ns, gvr.Resource)
	d.archive.WriteVirtualFile(yamlPath, data)

	return nil
}

func (d *Dumper) discoverResources() (*resourceMap, error) {
	lists, err := d.discoveryClient.ServerPreferredResources()
	if err != nil {
		return nil, err
	}
	rm := &resourceMap{}

	ignoredResources := map[string]bool{
		"apiaccesses":       true, // Deprecated
		"componentstatuses": true, // Deprecated
		"endpoints":         true, // Deprecated
		"events":            true, // Too noisy
		"pods":              true, // Handled by workers
	}

	for _, list := range lists {
		gv, _ := schema.ParseGroupVersion(list.GroupVersion)
		for _, resource := range list.APIResources {
			if strings.Contains(resource.Name, "/") {
				continue
			}

			if ignoredResources[resource.Name] {
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
					log.Printf("Worker %d stopping app: %v", id, err)
					cancel()
					return
				}
				report := fmt.Sprintf("Error exporting logs: %v", err)
				errPath := filepath.Join(d.location, job.Pod.Namespace, job.Pod.Name)
				d.archive.WriteVirtualFile(errPath, []byte(report))
			}

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
	case "pg":
		return podLabels["pgo-pg-database"] == "true"
	case "pgo":
		return podLabels["pgo-pg-database"] == "true"
	case "pgv2":
		return podLabels["pgv2.percona.com/version"] != "" &&
			podLabels["postgres-operator.crunchydata.com/instance"] != ""
	}

	return false
}

func (d *Dumper) exportPodSummaryAndFiles(ctx context.Context, job exportJob) {
	for _, cr := range d.crTypes {
		if !matchesCR(cr, job.Pod.Labels) {
			continue
		}

		if !d.skipPodSummary {
			d.getSummary(ctx, job, cr, d.PodSummaryPath(job.Pod.Namespace, job.Pod.Name))
		}

		d.getIndividualFiles(ctx, job, cr)
	}
}

func isSpaceError(err error) bool {
	return strings.Contains(err.Error(), "no space left on device")
}
