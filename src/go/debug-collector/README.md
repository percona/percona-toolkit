#Debug collector tool

Collects data for debugging from a k8s/opeshift cluster and creates a tar.gz archive with it.
Archive name will be "cluster-dump.tar.gz" and it will be saved in the same location where you will run tool

###Data that will be collected
        "pods",
		"replicasets",
		"deployments",
		"statefulsets",
		"replicationcontrollers",
		"events",
		"configmaps",
		"secrets",
		"cronjobs",
		"jobs",
		"podsecuritypolicies",
		"poddisruptionbudgets",
		"perconaxtradbbackups",
		"perconaxtradbclusterbackups",
		"perconaxtradbclusterrestores",
		"perconaxtradbclusters",
		"clusterrolebindings",
		"clusterroles",
		"rolebindings",
		"roles",
		"storageclasses",
		"persistentvolumeclaims",
		"persistentvolumes",
        "modes",
        "pxc/psmdb" (depend on 'resource'  flag)


###Usage 
Tool accept 3 flags:
    1) resource: name of required custom resource ("pxc" is default)
    2) namespace: namespace from where you need to collect data. If empty data will be collected from all namespaces
    3) cluster: name for exact pxc/psmdb cluster. If empty tool will collect all "resource" 

###Requirements
Installed and configured 'kubectl' is needed  for work

