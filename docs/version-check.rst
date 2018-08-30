.. _version-check:

================================================================================
Version Checking
================================================================================

Complex software projects (such as MySQL flavors) always have versions with
minor or major compatibility problems, regressions and bugs, etc. It is too
difficult to take care about all these compatibility nuances for a human, and
this is the reason for a |version-check| feature to exist.

The feature allows compatible tools to query the Version Check database and
print advice on any potential risks associated with any of the relevant
software versions.

Usage
-----

*Version Check* was implemented in |pt| 2.1.4, and was enabled by default in
version 2.2.1. Currently it is supported by most tools in |pt|, |pxb|, and
|pmm|.

Being called with Version Check enabled,the tool that supports this feature
connects to a dedicated Percona server via a secure HTTPS channel. It checks
its own version to query the server for possible updates, and also checks
versions of the following software:

* operating system
* Percona Monitoring and Management (PMM)
* MySQL
* Perl
* MySQL driver for Perl (DBD::mysql)
* Percona Toolkit

Then it checks for and warns about versions with known problems.

To guide the development of future |version-check| requirements, each request
is logged by the server. Stored information includes software version numbers
and the unique ID of a checked system. The ID is generated either at
installation or when the |version-check| query is done for the first time.

.. note::

   Prior to version 3.0.7 of |pt|, the system ID was calculated as an MD5 hash
   of the hostname, and starting from |pt| 3.0.7 it is generated as a random
   number.

Disabling Version Check
-----------------------

Although the |version-check| feature does not collect any personal information,
you might prefer to disable this feature, either onetime or permanently.
To disable it onetime, use ``--no-version-check`` option when invoking the tool
from a Percona product which supports it.

Disabling |version-check| permanently can be done by placing
``--no-version-check`` option into the configuration file of a Percona product
(see correspondent documentation for exact file name and syntax). For example,
in case of |pt| `this can be done <https://www.percona.com/doc/percona-toolkit/LATEST/configuration_files.html>`_ in a global configuration file ``/etc/percona-toolkit/percona-toolkit.conf``::

  # Disable Version Check for all tools:
  no-version-check

.. |pmm| replace:: PMM (Percona Monitoring and Management)
.. |pt| replace:: Percona Toolkit
.. |pxb| replace:: Percona XtraBackup
.. |version-check| replace:: *version checking*
