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

Supported Flags
================

``--config``

List of Percona Toolkit configuration file(s) separated by a comma without an equal sign. Must be a first flag. Uses default config file locations if not specified.

``--resource``

Targeted custom resource name. Supported values:

* ``pxc`` - PXC

* ``psmdb`` - MongoDB

* ``pg`` - PostgreSQL Operator v1 (deprecated)

* ``pgv2`` - PostgreSQL Operator v2

* ``ps`` - MySQL

* ``none`` - Collect only general Kubernetes data, do not collect anything specific to the particular operator).

* ``auto`` - Auto-detect custom resource

Default: ``auto``

``--namespace``

Targeted namespace. By default data will be collected from all namespaces

``--cluster``

Targeted cluster. By default data from all available clusters to be collected

``--kubeconfig``

Path to kubeconfig. Default configuration be used if none specified

``--forwardport``

Port to use when collecting database-specific summaries. By default, 3306 will be used for PXC and MySQL, 27017 for MongoDB, and 5432 for PostgreSQL

``--version``

Print version info

Requirements
============

- Installed, configured, and available in PATH ``kubectl``
- Installed, configured, and available in PATH ``pt-mysql-summary`` for PXC and MySQL
- Installed, configured, and available in PATH ``mysql`` for PXC and MySQL
- Installed, configured, and available in PATH ``pt-mongodb-summary`` for MongoDB
- Installed, configured, and available in PATH ``psql`` for PostgreSQL

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

Authors
=======

Max Dudin, Andrii Dema, Carlos Salguero, Sveta Smirnova

ABOUT PERCONA TOOLKIT
=====================

This tool is part of Percona Toolkit, a collection of advanced command-line
tools for MySQL developed by Percona.  Percona Toolkit was forked from two
projects in June, 2011: Maatkit and Aspersa.  Those projects were created by
Baron Schwartz and primarily developed by him and Daniel Nichter.  Visit
`http://www.percona.com/software/ <http://www.percona.com/software/>`_ to learn about other free, open-source
software from Percona.

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2011-2026 Percona LLC and/or its affiliates.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue \`man perlgpl' or \`man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.

VERSION
=======

:program:`pt-k8s-debug-collector` 3.7.1

