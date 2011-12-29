Release Notes
*************

v1.0.2 released 2011-12-22
==========================

Percona Toolkit 1.0.2 has been released.  Ten little bugs and typos were
fixed in this release.  The debug switch MKDEBUG was changed to PTDEBUG.
Otherwise, no features were added, removed, or changed.  If you are using
Percona Toolkit 1.0.1, it is safe and beneficial to upgrade to 1.0.2.
Thank you to all those who submitted bug reports.

Download the latest release of Percona Toolkit from
http://www.percona.com/software/percona-toolkit/
or the Percona Software Repositories
(http://www.percona.com/docs/wiki/repositories:start).

Changelog
---------

* Fixed bug 856065: pt-trend does not work
* Fixed bug 887688: Prepared statements crash pt-query-digest
* Fixed bug 903513: MKDEBUG should be PTDEBUG
* Fixed bug 857091: pt-sift downloads http://percona.com/get/pt-pmp, which does not work
* Fixed bug 857104: pt-sift tries to invoke mext, should be pt-mext
* Fixed bug 884504: pt-stalk doesn't check pt-collect
* Fixed bug 821717: pt-tcp-model --type=requests crashes
* Fixed bug 844038: pt-online-schema-change documentation example w/drop-tmp-table does not work
* Fixed bug 898663: Typo in pt-log-player documentation
* Fixed bug 903753: Typo in pt-table-checksum documentation

v1.0.1 released 2011-09-01
==========================

Percona Toolkit 1.0.1 has been released.  In July, Baron announced planned
changes to Maatkit and Aspersa development;[1]  Percona Toolkit is the
result.  In brief, Percona Toolkit is the combined fork of Maatkit and
Aspersa, so although the toolkit is new, the programs are not.  That means
Percona Toolkit 1.0.1 is mature, stable, and production-ready.  In fact,
it's even a little more stable because we fixed a few bugs in this release.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/
or the Percona Software Repositories
(http://www.percona.com/docs/wiki/repositories:start).

Although Maatkit and Aspersa development use Google Code, Percona Toolkit
uses Launchpad: https://launchpad.net/percona-toolkit

[1] http://www.xaprb.com/blog/2011/07/06/planned-change-in-maatkit-aspersa-development/

Changelog
---------

* Fixed bug 819421: MasterSlave::is_replication_thread() doesn't match all
* Fixed bug 821673: pt-table-checksum doesn't include --where in min max queries
* Fixed bug 821688: pt-table-checksum SELECT MIN MAX for char chunking is wrong
* Fixed bug 838211: pt-collect: line 24: [: : integer expression expected
* Fixed bug 838248: pt-collect creates a "5.1" file

v0.9.5 released 2011-08-04
==========================

Percona Toolkit 0.9.5 represents the completed transition from Maatkit and Aspersa.  There are no bug fixes or new features, but some features have been removed (like --save-results from pt-query-digest).  This release is the starting point for the 1.0 series where new development will happen, and no more changes will be made to the 0.9 series.

Changelog
---------

* Forked, combined, and rebranded Maatkit and Aspersa as Percona Toolkit.
