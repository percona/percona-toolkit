.. _pt-k8s-debug-collector:

==================================
:program:`pt-k8s-debug-collector`
==================================

Collects debug data (logs, resource statuses etc.) from a k8s/OpenShift cluster. Data is packed into the ``cluster-dump.tar.gz`` archive in the current working directory. 

Data that will be collected
===========================

.. code-block:: bash

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


Usage
=====

``pt-k8s-debug-collector <flags>``

Flags:

``--resource` targeted custom resource name (default "pxc")``

``--namespace` targeted namespace. By default data will be collected from all namespaces``

``--cluster` targeted pxc/psmdb cluster. By default data from all available clusters to be collected``

Requirements
============

- Installed and configured ``kubectl``
- Installed and configured ``pt-mysql-summary``
- Installed and configured ``pt-mongodb-summary`` 
