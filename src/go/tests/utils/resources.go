package utils

const (
	REPL_CONTROLLER_MOCK_RESOURCE = `
apiVersion: v1
kind: ReplicationController
metadata:
  name: test-rc
  labels:
    app: test
spec:
  replicas: 1
  selector:
    app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: nginx
        image: nginx:latest`

	JOB_MOCK_RESOURSE = `
apiVersion: batch/v1
kind: Job
metadata:
  name: dummy-job
spec:
  template:
    spec:
      containers:
      - name: pause
        image: k8s.gcr.io/pause:3.1
      restartPolicy: Never`

	CRON_JOB_MOCK_RESOURCE = `
apiVersion: batch/v1
kind: CronJob
metadata:
  name: dummy-cronjob
spec:
  schedule: "0 0 1 1 *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: pause
            image: k8s.gcr.io/pause:3.1
          restartPolicy: OnFailure`

	PSMDB_BACKUP_MOCK_RESOURCE = `
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: test-export-psmdb
spec:
  psmdbCluster: dummy
  storageName: s3-us-east`

	PSMDB_RESTORE_MOCK_RESOURCE = `
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBRestore
metadata:
  name: dummy-restore-psmdb
spec:
  psmdbCluster: dummy
  backupName: test-export-psmdb`

	PS_BACKUP_MOCK_RESOURCE = `
apiVersion: ps.percona.com/v1
kind: PerconaServerMySQLBackup
metadata:
  name: test-export-ps
spec:
  clusterName: dummy
  storageName: s3-us-east`

	PS_RESTORE_MOCK_RESOURCE = `
apiVersion: ps.percona.com/v1
kind: PerconaServerMySQLRestore
metadata:
  name: dummy-restore-ps
spec:
  clusterName: dummy
  backupName: test-export-ps`

	PGV2_BACKUP_MOCK_RESOURCE = `
apiVersion: pgv2.percona.com/v2
kind: PerconaPGBackup
metadata:
  name: test-export-pgv2
spec:
  pgCluster: dummy
  repoName: repo1`

	PGV2_RESTORE_MOCK_RESOURCE = `
apiVersion: pgv2.percona.com/v2
kind: PerconaPGRestore
metadata:
  name: dummy-restore-pgv2
spec:
  pgCluster: dummy
  repoName: repo1
  backupName: test-export-pgv2`

	PGO_BACKUP_MOCK_RESOURCE = `
apiVersion: pg.percona.com/v1
kind: Pgtask
metadata:
  labels:
    pg-cluster: cluster1
    pgouser: admin
  name: cluster1-backrest-full-backup
spec:
  name: cluster1-backrest-full-backup
  parameters:
    backrest-command: backup
    backrest-opts: --type=full --repo1-retention-full=5
    backrest-s3-verify-tls: "true"
    backrest-storage-type: ""
    job-name: cluster1-backrest-full-backup
    pg-cluster: cluster1
  tasktype: backrest`

	PGO_RESTORE_MOCK_RESOURCE = `
apiVersion: pg.percona.com/v1
kind: Pgtask
metadata:
  labels:
    pg-cluster: cluster1
    pgouser: admin
  name: cluster1-backrest-restore
  namespace: pgo
spec:
  name: cluster1-backrest-restore
  namespace: pgo
  parameters:
    backrest-restore-from-cluster: cluster1
    backrest-restore-opts: --type=time --target="2021-04-16 15:13:32"
    backrest-storage-type: posix
    backrest-s3-verify-tls: "true"
  tasktype: restore`

	PXC_BACKUP_MOCK_RESOURCE = `
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterBackup
metadata:
  name: test-export-pxc
spec:
  pxcCluster: dummy
  storageName: s3-us-east`

	PXC_RESTORE_MOCK_RESOURCE = `
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBClusterRestore
metadata:
  name: dummy-restore-pxc
spec:
  pxcCluster: dummy
  backupName: test-export-pxc`
)
