Release Notes
*************

v2.1.1 released 2012-04-03
==========================

Percona Toolkit 2.1.1 has been released.  This is the first release in the
new 2.1 series which supersedes the 2.0 series.  We will continue to fix bugs
in 2.0, but 2.1 is now the focus of development.

2.1 introduces a lot of new code for:

* pt-online-schema-change (completely redesigned)
* pt-mysql-summary (completely redesigned)
* pt-summary (completely redesigned)
* pt-fingerprint (new tool)
* pt-table-usage (new tool)

There were also several bug fixes.

The redesigned tools are meant to replace their 2.0 counterparts because
the 2.1 versions have the same or more functionality and they are simpler
and more reliable.  pt-online-schema-change was particularly enhanced to
be as safe as possible given that the tool is inherently risky.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/ or the Percona Software
Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Completely redesigned pt-online-schema-change
* Completely redesigned pt-mysql-summary
* Completely redesigned pt-summary
* Added new tool: pt-table-usage
* Added new tool: pt-fingerprint
* Fixed bug 955860: pt-stalk doesn't run vmstat, iostat, and mpstat for --run-time
* Fixed bug 960513: SHOW TABLE STATUS is used needlessly
* Fixed bug 969726: pt-online-schema-change loses foreign keys
* Fixed bug 846028: pt-online-schema-change does not show progress until completed
* Fixed bug 898695: pt-online-schema-change add useless ORDER BY
* Fixed bug 952727: pt-diskstats shows incorrect wr_mb_s
* Fixed bug 963225: pt-query-digest fails to set history columns for disk tmp tables and disk filesort
* Fixed bug 967451: Char chunking doesn't quote column name
* Fixed bug 972399: pt-table-checksum docs are not rendered right
* Fixed bug 896553: Various documentation spelling fixes
* Fixed bug 949154: pt-variable-advisor advice for relay-log-space-limit
* Fixed bug 953461: pt-upgrade manual broken 'output' section
* Fixed bug 949653: pt-table-checksum docs don't mention risks posed by inconsistent schemas

v2.0.4 released 2012-03-07
==========================

Percona Toolkit 2.0.4 has been released.  23 bugs were fixed in this release,
and three new features were implemented.  First, --filter was added to pt-kill
which allows for arbitrary --group-by.  Second, pt-online-schema-change now
requires that its new --execute option be given, else the tool will just check
the tables and exit.  This is a safeguard to encourage users to read the
documentation, particularly when replication is involved.  Third, pt-stalk
also received a new option: --[no]stalk.  To collect immediately without
stalking, specify --no-stalk and the tool will collect once and exit.

This release is completely backwards compatible with previous 2.0 releases.
Given the number of bug fixes, it's worth upgrading to 2.0.4.

Changelog
---------

* Added --filter to pt-kill to allow arbitrary --group-by
* Added --[no]stalk to pt-stalk (bug 932331)
* Added --execute to pt-online-schema-change (bug 933232)
* Fixed bug 873598: pt-online-schema-change doesn't like reserved words in column names
* Fixed bug 928966: pt-pmp still uses insecure /tmp
* Fixed bug 933232: pt-online-schema-change can break replication
* Fixed bug 941225: Use of qw(...) as parentheses is deprecated at pt-kill line 3511
* Fixed bug 821694: pt-query-digest doesn't recognize hex InnoDB txn IDs
* Fixed bug 894255: pt-kill shouldn't check if STDIN is a tty when --daemonize is given
* Fixed bug 916999: pt-table-checksum error: DBD::mysql::st execute failed: called with 2 bind variables when 6 are needed
* Fixed bug 926598: DBD::mysql bug causes pt-upgrade to use wrong precision (M) and scale (D)
* Fixed bug 928226: pt-diskstats illegal division by zero
* Fixed bug 928415: Typo in pt-stalk doc: --trigger should be --function
* Fixed bug 930317: pt-archiver doc refers to nonexistent pt-query-profiler
* Fixed bug 930533: pt-sift looking for *-processlist1; broken compatibility with pt-stalk
* Fixed bug 932331: pt-stalk cannot collect without stalking
* Fixed bug 932442: pt-table-checksum error when column name has two spaces
* Fixed bug 932883: File Debian bug after each release
* Fixed bug 940503: pt-stalk disk space checks wrong on 32bit platforms
* Fixed bug 944420: --daemonize doesn't always close STDIN
* Fixed bug 945834: pt-sift invokes pt-diskstats with deprecated argument
* Fixed bug 945836: pt-sift prints awk error if there are no stack traces to aggregate
* Fixed bug 945842: pt-sift generates wrong state sum during processlist analysis
* Fixed bug 946438: pt-query-digest should print a better message when an unsupported log format is specified
* Fixed bug 946776: pt-table-checksum ignores --lock-wait-timeout
* Fixed bug 940440: Bad grammar in pt-kill docs

v2.0.3 released 2012-02-03
==========================

Percona Toolkit 2.0.3 has been released.  The development team was very
busy last month making this release significant: two completely
redesigned and improved tools, pt-diskstats and pt-stalk, and 20 bug fixes.

Both pt-diskstats and pt-stalk were redesigned and rewritten from the ground
up.  This allowed us to greatly improve these tools' functionality and
increase testing for them.  The accuracy and output of pt-diskstats was
enhanced, and the tool was rewritten in Perl.  pt-collect was removed and
its functionality was put into a new, enhanced pt-stalk.  pt-stalk is now
designed to be a stable, long-running daemon on a variety of common platforms.
It is worth re-reading the documentation for each of these tools.

The 20 bug fixes cover a wide range of problems.  The most important are
fixes to pt-table-checksum, pt-iostats, and pt-kill.  Apart from pt-diskstats,
pt-stalk, and pt-collect (which was removed), no other tools were changed
in backwards-incompatible ways, so it is worth reviewing the full changelog
for this release and upgrading if you use any tools which had bug fixes.

Thank you to the many people who reported bugs and submitted patches.

Download the latest release of Percona Toolkit 2.0 from
http://www.percona.com/software/percona-toolkit/
or the Percona Software Repositories
(http://www.percona.com/docs/wiki/repositories:start).

Changelog
---------

* Completely redesigned pt-diskstats
* Completely redesigned pt-stalk
* Removed pt-collect and put its functionality in pt-stalk
* Fixed bug 871438: Bash tools are insecure
* Fixed bug 897758: Failed to prepare TableSyncChunk plugin: Use of uninitialized value $args{"chunk_range"} in lc at pt-table-sync line 3055
* Fixed bug 919819: pt-kill --execute-command creates zombies
* Fixed bug 925778: pt-ioprofile doesn't run without a file
* Fixed bug 925477: pt-ioprofile docs refer to pt-iostats
* Fixed bug 857091: pt-sift downloads http://percona.com/get/pt-pmp, which does not work
* Fixed bug 857104: pt-sift tries to invoke mext, should be pt-mext
* Fixed bug 872699: pt-diskstats: rd_avkb & wr_avkb derived incorrectly
* Fixed bug 897029: pt-diskstats computes wrong values for md0
* Fixed bug 882918: pt-stalk spams warning if oprofile isn't installed
* Fixed bug 884504: pt-stalk doesn't check pt-collect
* Fixed bug 897483: pt-online-schema-change "uninitialized value" due to update-foreign-keys-method
* Fixed bug 925007: pt-online-schema-change Use of uninitialized value $tables{"old_table"} in concatenation (.) or string at line 4330
* Fixed bug 915598: pt-config-diff ignores --ask-pass option
* Fixed bug 919352: pt-table-checksum changes binlog_format even if already set to statement
* Fixed bug 921700: pt-table-checksum doesn't add --where to chunk size test on replicas
* Fixed bug 921802: pt-table-checksum does not recognize --recursion-method=processlist
* Fixed bug 925855: pt-table-checksum index check is case-sensitive
* Fixed bug 821709: pt-show-grants --revoke and --separate don't work together
* Fixed bug 918247: Some tools use VALUE instead of VALUES

v2.0.2 released 2012-01-05
==========================

Percona Toolkit 2.0.2 fixes one critical bug: pt-table-sync --replicate
did not work with character values, causing an "Unknown column" error.
If using Percona Toolkit 2.0.1, you should upgrade to 2.0.2.

Download the latest release of Percona Toolkit 2.0 from
http://www.percona.com/software/percona-toolkit/
or the Percona Software Repositories
(http://www.percona.com/docs/wiki/repositories:start).

Changelog
---------

* Fixed bug 911996: pt-table-sync --replicate causes "Unknown column" error

v2.0.1 released 2011-12-30
==========================

The Percona Toolkit development team is proud to announce a new major version:
2.0.  Beginning with Percona Toolkit 2.0, we are overhauling, redesigning, and
improving the major tools.  2.0 tools are therefore not backwards compatible
with 1.0 tools, which we still support but will not continue to develop.

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
