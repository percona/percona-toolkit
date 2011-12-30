Release Notes
*************

v2.0.1 released 2011-12-30
==========================

The Percona Toolkit development team is proud to announce the next genc
na Toolkit development team is proud to announce a new major version: 2.0.
Beginning with Percona Toolkit 2.0, we are overhauling, redesigning, and
improving the major tools.  2.0 tools are therefore not backwards compatible
with 1.0 tools, which= we still support but will not continue to develop.

New in Percona Toolkit 2.0.1 is a completely redesigned pt-table-checksum.
The original pt-table-checksum 1.0 was rather complex, but it worked well
for many years.  By contrast, the new pt-table-checksum 2.0 is much simpler but
also much more efficient and reliable.  We spent months rethinking, redesigning,
and testing every aspect of the tool.  The three most significant changes:
pt-table-checksum 2.0 does only --replicate, it has only one chunking algorithm,
and its memory usage is stable even with hundreds of thousands of tables and
trillions of rows.  The tool is now dedicated to verifying MySQL replication
integrity, nothing else, which it does extremely well.

In Percona Toolkit 2.0.1 we also fixed various small bugs and forked ioprofile
and align (as pt-ioprofile and pt-align) from Aspersa.

If you still need functionalities in the original pt-table-checksum,
the latest Percona Toolkit 1.0 release remains available for download.
Otherwise, all new development in Percona Toolkit will happen in 2.0.

Download the latest release of Percona Toolkit 2.0 from
http://www.percona.com/software/percona-toolkit/
or the Percona Software Repositories
(http://www.percona.com/docs/wiki/repositories:start).

Changelog
---------

* Completely redesigned pt-table-checksum
* Fixed bug 856065: pt-trend does not work
* Fixed bug 887688: Prepared statements crash pt-query-digest
* Fixed bug 888286: align not part of percona-toolkit
* Fixed bug 897961: ptc 2.0 replicate-check error does not include hostname
* Fixed bug 898318: ptc 2.0 --resume with --tables does not always work
* Fixed bug 903513: MKDEBUG should be PTDEBUG
* Fixed bug 908256: Percona Toolkit should include pt-ioprofile
* Fixed bug 821717: pt-tcp-model --type=requests crashes
* Fixed bug 844038: pt-online-schema-change documentation example w/drop-tmp-table does not work
* Fixed bug 864205: Remove the query to reset @crc from pt-table-checksum
* Fixed bug 898663: Typo in pt-log-player documentation

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
