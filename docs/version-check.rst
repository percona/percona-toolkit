.. _version-check:

=====================
Version Check Feature
=====================

Complex software projects like MySQL (including Oracle MySQL, Percona Server,
and MariaDB) always have versions with minor or major compatibility problems,
regressions and bugs, etc. It is too difficult to take care about all these
compatibility nuances for a human, and this is the reason for a *Version Check*
feature to exist.

The feature allows compatible tools to make Version Check database calls and to
print advice on any potential risks associated with any of the relevant
software versions.

Usage
-----

*Version Check* is implemented in Percona Toolkit starting from the version
2.1.4, and is enabled by default in versions starting from 2.2.1. Currently it
is supported by most tools in Percona Toolkit.

To enable Version Check (when it is disabled), one should call the tool that
supports this feature with an option :option:`--version-check`. Being called
with Version Check enabled, the tool connects to the Percona Version Check
database server through a secure HTTPS channel.

While this query is done, the tool checks its own version to query server for
possible updates, and also checks versions of the following software:

* the operating system,
* Percona Monitoring and Management (PMM),
* MySQL,
* Perl,
* MySQL driver for Perl (DBD::mysql),
* Percona Toolkit. 

Then it checks for and warns about versions with known problems. Warnings
about updates or known problems are printed to STDOUT before the tool's normal
output, and the feature should never interfere with the normal operation of the
tool.

To guide the development of future Version Check requirements, each request is
logged by the server, including software version numbers and the unique ID of a
checked system. The ID is generated either at installation or when the version
check query is done for the first time.

.. note:: Prior to version 3.0.7 system ID was calculated as an MD5 hash of the
   hostname, and starting from Percona Toolkit 3.0.7 it is generated as a
   random number.

Disabling Version Check
-----------------------

Because of dealing with potentially sensitive information, Version Check
feature can be easily disabled by the user with the
:option:`--no-version-check` option. It can be also disabled globally in the
`configuration file, and in this case tool can be called with
:option:`--version-check` to activate it temporarily.
