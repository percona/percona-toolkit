=======================================
 Installation
=======================================

.. You can either download Percona Toolkit manually from the website
 or use the official Percona software repositories for your system.

You can install Percona Toolkit 3.0.0 release candidate
from the official Percona software repositories for your system.

.. contents::
   :local:
..
 Downloading Percona Toolkit
 ===========================
 
 Visit http://www.percona.com/software/percona-toolkit/
 to download the latest release of Percona Toolkit.
 Alternatively, you can get the latest release using the command line:
 
 .. code-block:: bash
 
     wget percona.com/get/percona-toolkit.tar.gz
  
     wget percona.com/get/percona-toolkit.rpm
  
     wget percona.com/get/percona-toolkit.deb
 
 You can also get individual tools from the latest release:
 
 .. code-block:: bash
 
     wget percona.com/get/TOOL
 
 Replace ``TOOL`` with the name of any tool, for example::
 
   wget percona.com/get/pt-summary

Installing Percona Toolkit on Debian or Ubuntu
==============================================

1. Fetch the repository packages from Percona web:

   .. code-block:: bash

      wget https://repo.percona.com/apt/percona-release_0.1-4.$(lsb_release -sc)_all.deb

#. Install the downloaded package with :program:`dpkg`
   by running the following command as root or with :program:`sudo`:

   .. code-block:: bash

      sudo dpkg -i percona-release_0.1-4.$(lsb_release -sc)_all.deb

#. Once you install this package, the Percona repositories should be added.
   You can check the repository configuration
   in the :file:`/etc/apt/sources.list.d/percona-release.list` file.

#. Update the local cache:

   .. code-block:: bash

      sudo apt-get update

#. Install the ``percona-toolkit`` package:

   .. code-block:: bash

      sudo apt-get install percona-toolkit

.. _apt-testing-repo:

Testing and Experimental Repositories
-------------------------------------

Percona offers pre-release builds from the testing repo,
and early-stage development builds from the experimental repo.
To enable them, add either ``testing`` or ``experimental`` at the end
of the Percona repository definition in your repository file
(by default, :file:`/etc/apt/sources.list.d/percona-release.list`).

For example, if you are running Debian 8 ("jessie")
and want to install the latest testing builds,
the definitions should look like this::

  deb http://repo.percona.com/apt jessie main testing
  deb-src http://repo.percona.com/apt jessie main testing

If you are running Ubuntu 14.04 LTS (Trusty Tahr)
and want to install the latest experimental builds,
the definitions should look like this::

  deb http://repo.percona.com/apt trusty main experimental
  deb-src http://repo.percona.com/apt trusty main experimental

Pinning the Packages
--------------------

If you want to pin your packages to avoid upgrades,
create a new file :file:`/etc/apt/preferences.d/00percona.pref`
and add the following lines to it::

  Package: *
  Pin: release o=Percona Development Team
  Pin-Priority: 1001

For more information about pinning,
refer to the official `Debian Wiki <http://wiki.debian.org/AptPreferences>`_.

Installing Percona Toolkit on Red Hat or CentOS
===============================================

1. Install the Percona repository package:

   .. code-block:: bash

      $ sudo yum install http://www.percona.com/downloads/percona-release/redhat/0.1-4/percona-release-0.1-4.noarch.rpm

   You should see the following if successful: ::

      Installed:
        percona-release.noarch 0:0.1-4

      Complete!

#. Check that the packages are available:

   .. code-block:: bash

      $ yum list | grep percona-toolkit

   You should see output similar to the following:

   .. code-block:: text

    percona-toolkit.noarch                     3.0.0-rc                    percona-release-noarch
 
#. Install the |PSMDB| packages:

   .. code-block:: bash

      $ sudo yum install percona-toolkit

.. _yum-testing-repo:

Testing and Experimental Repositories
-------------------------------------

Percona offers pre-release builds from the testing repo,
and early-stage development builds from the experimental repo.
You can enable either one in the Percona repository configuration file
:file:`/etc/yum.repos.d/percona-release.repo`.
There are three sections in this file,
for configuring corresponding repositories:

* stable release
* testing
* experimental

The latter two repositories are disabled by default.

If you want to install the latest testing builds,
set ``enabled=1`` for the following entries: ::

  [percona-testing-$basearch]
  [percona-testing-noarch]

If you want to install the latest experimental builds,
set ``enabled=1`` for the following entries: ::

  [percona-experimental-$basearch]
  [percona-experimental-noarch]

.. note:: As of version 3.0,
   Percona Toolkit is not available in the ``noarch`` repo.
   Make sure that you enable the ``basearch`` repo
   when installing or upgrading to Percona Toolkit 3.0 or later.

