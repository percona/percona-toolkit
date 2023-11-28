package dumper

import "regexp"

var resourcesRe = regexp.MustCompile(`(\w+).percona\.com`)

type resourceCompilation struct {
	k8sResources []string
	filePaths    []string
}

var resourcesMapping = map[string]resourceCompilation{
	"common": resourceCompilation{
		k8sResources: []string{
			"pods",
			"replicasets",
			"deployments",
			"statefulsets",
			"replicationcontrollers",
			"events",
			"configmaps",
			"cronjobs",
			"jobs",
			"poddisruptionbudgets",
			"clusterrolebindings",
			"clusterroles",
			"rolebindings",
			"roles",
			"storageclasses",
			"persistentvolumeclaims",
			"persistentvolumes",
		},
	},

	"pg": resourceCompilation{
		k8sResources: []string{
			"perconapgclusters",
			"pgclusters",
			"pgpolicies",
			"pgreplicas",
			"pgtasks",
		},
	},
	"pgv2": resourceCompilation{
		k8sResources: []string{
			"perconapgbackups",
			"perconapgclusters",
			"perconapgrestores",
		},
	},
	"pxc": resourceCompilation{
		k8sResources: []string{
			"perconaxtradbclusterbackups",
			"perconaxtradbclusterrestores",
			"perconaxtradbclusters",
		},
		filePaths: []string{
			"var/lib/mysql/mysqld-error.log",
			"var/lib/mysql/innobackup.backup.log",
			"var/lib/mysql/innobackup.move.log",
			"var/lib/mysql/innobackup.prepare.log",
			"var/lib/mysql/grastate.dat",
			"var/lib/mysql/gvwstate.dat",
			"var/lib/mysql/mysqld.post.processing.log",
			"var/lib/mysql/auto.cnf",
		},
	},
	"ps": resourceCompilation{
		k8sResources: []string{
			"perconaservermysqlbackups",
			"perconaservermysqlrestores",
			"perconaservermysqls",
		},
	},
	"psmdb": resourceCompilation{
		k8sResources: []string{
			"perconaservermongodbbackups",
			"perconaservermongodbrestores",
			"perconaservermongodbs",
		},
	},
}
