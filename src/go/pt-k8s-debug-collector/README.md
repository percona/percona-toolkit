# Debug collector tool

Collects debug data (logs, resource statuses etc.) from a k8s/OpenShift cluster. Data is packed into the `cluster-dump.tar.gz` archive in the current working directory. 

## Data that will be collected

### Data, collected for all resources

```
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
"your-custom-resource" (depends on 'resource' flag)

```

### Data, collected for PXC

```
"perconaxtradbbackups",
"perconaxtradbclusterbackups",
"perconaxtradbclusterrestores",
"perconaxtradbclusters"
```

### Individual files, collected for PXC

```
"var/lib/mysql/mysqld-error.log",
"var/lib/mysql/innobackup.backup.log",
"var/lib/mysql/innobackup.move.log",
"var/lib/mysql/innobackup.prepare.log",
"var/lib/mysql/grastate.dat",
"var/lib/mysql/gvwstate.dat",
"var/lib/mysql/mysqld.post.processing.log",
"var/lib/mysql/auto.cnf"
```

### Data, collected for MongoDB

```
"perconaservermongodbbackups",
"perconaservermongodbrestores",
"perconaservermongodbs"
```

## Usage 

`pt-k8s-debug-collector <flags>`

Flags:

`--resource` targeted custom resource name (default "pxc")

`--namespace` targeted namespace. By default, data will be collected from all namespaces

`--cluster` targeted pxc/psmdb cluster. By default, data from all available clusters to be collected 

## Requirements

- Installed and configured 'kubectl'
- Installed and configured 'pt-mysql-summary'
- Installed and configured 'pt-mongodb-summary' 

