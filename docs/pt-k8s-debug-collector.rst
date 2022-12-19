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

Data, collected for PXC
~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "perconaxtradbbackups",
   "perconaxtradbclusterbackups",
   "perconaxtradbclusterrestores",
   "perconaxtradbclusters"

Summary, collected for PXC (available in file summary.txt)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "pt-mysql-summary"

Individual files, collected for PXC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "var/lib/mysql/mysqld-error.log",
   "var/lib/mysql/innobackup.backup.log",
   "var/lib/mysql/innobackup.move.log",
   "var/lib/mysql/innobackup.prepare.log",
   "var/lib/mysql/grastate.dat",
   "var/lib/mysql/gvwstate.dat",
   "var/lib/mysql/mysqld.post.processing.log",
   "var/lib/mysql/auto.cnf"

Data, collected for MySQL
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "perconaservermysqlbackups",
   "perconaservermysqlrestores",
   "perconaservermysqls"

Summary, collected for MySQL (available in file summary.txt)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "pt-mysql-summary"

Data, collected for MongoDB
~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "perconaservermongodbbackups",
   "perconaservermongodbrestores",
   "perconaservermongodbs"

Summary, collected for MongoDB (available in file summary.txt)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "pt-mongodb-summary"

Data, collected for PostgreSQL
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "perconapgclusters",
   "pgclusters",
   "pgpolicies",
   "pgreplicas",
   "pgtasks"

Summary, collected for PostgreSQL (available in file summary.txt)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   "pg_gather"

Usage
=====

``pt-k8s-debug-collector <flags>``

Supported Flags:
================

``--resource`` 

Targeted custom resource name. Supported values: 

* ``pxc`` - PXC 

* ``psmdb`` - MongoDB

* ``pg`` - PostgreSQL 

* ``ps`` - MySQL

* ``none`` - Collect only general Kubernetes data, do not collect anything specific to the particular operator). 

Default: ``none``

``--namespace`` 

Targeted namespace. By default data will be collected from all namespaces

``--cluster`` 

Targeted cluster. By default data from all available clusters to be collected

``--kubeconfig`` 

Path to kubeconfig. Default configuration be used if none specified

``--forwardport``

Port to use when collecting database-specific summaries. By default, 3306 will be used for PXC and MySQL, 27017 for MongoDB, and 5432 for PostgreSQL

Requirements
============

- Installed, configured, and available in PATH ``kubectl``
- Installed, configured, and available in PATH ``pt-mysql-summary`` for PXC and MySQL
- Installed, configured, and available in PATH ``pt-mongodb-summary`` for MongoDB

Known Issues
============

On Kubernetes 1.21 - 1.24 warning is printed:

.. code-block:: bash

    2022/12/15 17:43:16 Error: get resource podsecuritypolicies in namespace default: error: <nil>, stderr: Warning: policy/v1beta1 PodSecurityPolicy is deprecated in v1.21+, unavailable in v1.25+
 , stdout: apiVersion: v1
    items: []
    kind: List
    metadata:
      resourceVersion: ""

This warning is harmless and does not affect data collection. We will remove podsecuritypolicies once everyone upgrade to Kubernetes 1.25 or newer. Before that we advise to ignore this warning.