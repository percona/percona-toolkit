Release Notes
*************

v2.1.4 released 2012-09-20
==========================

Percona Toolkit 2.1.4 has been released.  This release includes 26 bug fixes and three new features: Making pt-table-checksum work with Percona XtraDB Cluster, adding a --run-time option to pt-table-checksum, and implementing the "Version Check" feature, enabled through the --version-check switch.  For further information on --version-check, see http://www.mysqlperformanceblog.com/2012/09/10/introducing-the-version-check-feature-in-percona-toolkit/.  The bug fixes are widely assorted.  The following highlights some of the more interesting and "hot" bugs:

* Fixed bug 1017626: pt-table-checksum doesn't work with Percona XtraDB Cluster

Note that this requires Percona XtraDB Cluster 5.5.27-23.6 or newer, as the fix depends on this bug https://bugs.launchpad.net/codership-mysql/+bug/1023911 being resolved.

* Fixed bug 1034170: pt-table-checksum --defaults-file isn't used for slaves

Previously, users had no recourse but using --recursion-method in conjunction with a dsn table to sidestep this bug, so this fix is a huge usability gain.  This was caused by the toolkit not copying the -F portion of the main dsn.

* Fixed bug 1039184: pt-upgrade error "I need a right_sth argument"

Which were stopping pt-upgrade from working on a MySQL 4.1 host.

* Fixed bug 1036747: pt-table-sync priv checks need to be removed

The same checks were removed in the previous release from pt-table-checksum, so this continues the trend.

* Fixed bug 1038995: pt-stalk --notify-by-email fails

This was a bug in our shell option parsing library, and would potentially affect any option starting with 'no'.

Like 2.1.3, this is another solid bug fix release, and 2.1 users are encouraged to upgrade.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* pt-table-checksum: Percona XtraDB Cluster support
* pt-table-checksum: Implemented the standard --run-time option
* Implemented the version-check feature in several tools, enabled with the --version-check option
* Fixed bug 856060: Document gdb dependency
* Fixed bug 1041394: Unquoted arguments to tr break the bash tools
* Fixed bug 1035311: pt-diskstats shows wrong device names
* Fixed bug 1036804: pt-duplicate-key-checker error parsing InnoDB table with no PK or unique keys
* Fixed bug 1022658: pt-online-schema-change dropping FK limitation isn't documented
* Fixed bug 1041372: pt-online-schema-changes fails if db+tbl name exceeds 64 characters
* Fixed bug 1029178: pt-query-digest --type tcpdump memory usage keeps increasing
* Fixed bug 1037211: pt-query-digest won't distill LOCK TABLES in lowercase
* Fixed bug 942114: pt-stalk warns about bad "find" usage
* Fixed bug 1035319: pt-stalk df -h throws away needed details
* Fixed bug 1038995: pt-stalk --notify-by-email fails
* Fixed bug 1038995: pt-stalk does not get all InnoDB lock data
* Fixed bug 952722: pt-summary should show information about Fusion-io cards
* Fixed bug 899415: pt-table-checksum doesn't work if slaves use RBR
* Fixed bug 954588: pt-table-checksum --check-slave-lag docs aren't clear
* Fixed bug 1034170: pt-table-checksum --defaults-file isn't used for slaves
* Fixed bug 930693: pt-table-sync and text columns with just whitespace
* Fixed bug 1028710: pt-table-sync base_count fails on n = 1000, base = 10
* Fixed bug 1034717: pt-table-sync division by zero error with varchar primary key
* Fixed bug 1036747: pt-table-sync priv checks need to be removed
* Fixed bug 1039184: pt-upgrade error "I need a right_sth argument"
* Fixed bug 1035260: sh warnings in pt-summary and pt-mysql-summary
* Fixed bug 1038276: ChangeHandler doesn't quote varchar columns with hex-looking values
* Fixed bug 916925: CentOS 5 yum dependency resolution for perl module is wrong
* Fixed bug 1035950: Percona Toolkit RPM should contain a dependency on perl-Time-HiRes

v2.1.3 released 2012-08-03
==========================

Percona Toolkit 2.1.3 has been released.  This release includes 31 bug fixes and one new feature: pt-kill --log-dsn to log information about killed queries to a table.  The bug fixes are widely assorted.  The following highlights some of the more interesting and "hot" bugs:

* Fixed bug 916168: pt-table-checksum privilege check fails on MySQL 5.5

pt-table-checksum used to check the user's privileges, but the method was not always reliable, and due to http://bugs.mysql.com/bug.php?id=61846 it became quite unreliable on MySQL 5.5.  So the privs check was removed altogether, meaning that the tool may fail later if the user's privileges are insufficient.

* Fixed bug 950294: pt-table-checksum should always create schema and tables with IF NOT EXISTS

In certain cases where the master and replicas have different schemas and/or tables, pt-table-checksum could break replication because the checksums table did not exist on a replica.

* Fixed bug 821703: pt-query-digest --processlist may crash
* Fixed bug 883098: pt-query-digest crashes if processlist has extra columns

Certain distributions of MySQL add extra columns to SHOW PROCESSLIST which caused pt-query-digest --processlist to crash at times.

* Fixed bug 941469: pt-kill doesn't reconnect if its connection is lost

pt-kill is meant to be a long-running daemon, so naturally it's important that it stays connected to MySQL.

* Fixed bug 1004567: pt-heartbeat --update --replace causes duplicate key error

The combination of these pt-heartbeat options could cause replication to break due to a duplicate key error.

* Fixed bug 1022628: pt-online-schema-change error: Use of uninitialized value in numeric lt (<) at line 6519

This bug was related to how --quiet was handled, and it could happen even if --quiet wasn't given on the command line.

All in all, this is solid bug fix release, and 2.1 users are encouraged to upgrade.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* pt-kill: Implemented --log-dsn to log info about killed queries to a table
* Fixed bug 1016127: Install hint for DBD::mysql is wrong
* Fixed bug 984915: DSNParser does not check success of --set-vars
* Fixed bug 889739: pt-config-diff doesn't diff quoted strings properly
* Fixed bug 969669: pt-duplicate-key-checker --key-types=k doesn't work
* Fixed bug 1004567: pt-heartbeat --update --replace causes duplicate key error
* Fixed bug 1028614: pt-index-usage ignores --database
* Fixed bug 940733: pt-ioprofile leaves behind temp directory
* Fixed bug 941469: pt-kill doesn't reconnect if its connection is lost
* Fixed bug 1016114: pt-online-schema-change docs don't mention default values
* Fixed bug 1020997: pt-online-schema-change fails when table is empty
* Fixed bug 1022628: pt-online-schema-change error: Use of uninitialized value in numeric lt (<) at line 6519
* Fixed bug 937225: pt-query-advisor OUTER JOIN advice in JOI.003 is confusing
* Fixed bug 821703: pt-query-digest --processlist may crash
* Fixed bug 883098: pt-query-digest crashes if processlist has extra columns
* Fixed bug 924950: pt-query-digest --group-by db may crash profile report
* Fixed bug 1022851: pt-sift error: PREFIX: unbound variable
* Fixed bug 969703: pt-sift defaults to '.' instead of '/var/lib/pt-talk'
* Fixed bug 962330: pt-slave-delay incorrectly computes lag if started when slave is already lagging
* Fixed bug 954990: pt-stalk --nostalk does not work
* Fixed bug 977226: pt-summary doesn't detect LSI RAID control
* Fixed bug 1030031: pt-table-checksum reports wrong number of DIFFS
* Fixed bug 916168: pt-table-checksum privilege check fails on MySQL 5.5 
* Fixed bug 950294: pt-table-checksum should always create schema and tables with IF NOT EXISTS
* Fixed bug 953141: pt-table-checksum ignores its default and explicit --recursion-method
* Fixed bug 1030975: pt-table-sync crashes if sql_mode includes ANSI_QUOTES
* Fixed bug 869005: pt-table-sync should always set REPEATABLE READ
* Fixed bug 903510: pt-tcp-model crashes in --type=requests mode on empty file
* Fixed bug 934310: pt-tcp-model --quantile docs wrong
* Fixed bug 980318: pt-upgrade results truncated if hostnames are long
* Fixed bug 821696: pt-variable-advisor shows too long of a snippet
* Fixed bug 844880: pt-variable-advisor shows binary logging as both enabled and disabled

v2.1.2 released 2012-06-12
==========================

Percona Toolkit 2.1.2 has been released.  This is a very important release because it fixes a critical bug in pt-table-sync (bug 1003014) which caused various failures.  All users of Percona Toolkit 2.1 should upgrade to this release.  There were 47 other bug fixes, several new options, and other changes.  The following is a high-level summary of the most important changes.

In addition to the critical bug fix mentioned above, another important pt-table-sync bug was fixed, bug 1002365: --ignore-* options did not work with --replicate.  The --lock-and-rename feature of the tool was also disabled unless running MySQL 5.5 or newer because it did not work reliably in earlier versions of MySQL.

Several important pt-table-checksum bugs were fixed.  First, a bug caused the tool to ignore the primary key.  Second, the tool did not wait for the checksum table to replicate, so it could select from a nonexistent table on a replica and crash.  Third, it did not check if all checksum queries were safe and chunk index with more than 3 columns could cause MySQL to scan many more rows than expected.

pt-online-schema-change received many improvements and fixes: it did not retry deadlocks, but now it does; --no-swap-tables caused an error; it did not handle column renames; it did not allow disabling foreign key checks; --dry-run always failed on tables with foreign keys; it used different keys for chunking and triggers; etc.  In short: pt-online-schema-change 2.1.2 is superior to 2.1.1.

Two pt-archiver bugs were fixed: bug 979092, --sleep conflicts with bulk operations; and bug 903379, --file doesn't create a file.

--recursion-method=none was implemented in pt-heartbeat, pt-online-schema-change, pt-slave-find, pt-slave-restart, pt-table-checksum, and pt-table-sync.  This allows these tools to avoid executing SHOW SLAVE STATUS which requires a privilege not available to Amazon RDS users.

Other bugs were fixed in pt-stalk, pt-variable-advisor, pt-duplicate-key-checker, pt-diskstats, pt-query-digest, pt-sift, pt-kill, pt-summary, and pt-deadlock-logger.

Percona Toolkit 2.1.2 should be backwards-compatible with 2.1.1, so users are strongly encouraged to upgrade.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* pt-heartbeat: Implemented --recursion-method=none
* pt-index-usage: MySQL 5.5 compatibility fixes
* pt-log-player: MySQL 5.5 compatibility fixes
* pt-online-schema-change: Added --chunk-index-columns
* pt-online-schema-change: Added --[no]check-plan
* pt-online-schema-change: Added --[no]drop-new-table
* pt-online-schema-change: Implemented --recursion-method=none
* pt-query-advisor: Added --report-type for JSON output
* pt-query-digest: Removed --[no]zero-bool
* pt-slave-delay: Added --database
* pt-slave-find: Implemented --recursion-method=none
* pt-slave-restart: Implemented --recursion-method=none
* pt-table-checksum: Added --chunk-index-columns
* pt-table-checksum: Added --[no]check-plan
* pt-table-checksum: Implemented --recursion-method=none
* pt-table-sync: Disabled --lock-and-rename except for MySQL 5.5 and newer
* pt-table-sync: Implemented --recursion-method=none
* Fixed bug 945079: Shell tools TMPDIR may break
* Fixed bug 912902: Some shell tools still use basename
* Fixed bug 987694: There is no --recursion-method=none option
* Fixed bug 886077: Passwords with commas don't work, expose part of password
* Fixed bug 856024: Lintian warnings when building percona-toolkit Debian package
* Fixed bug 903379: pt-archiver --file doesn't create a file
* Fixed bug 979092: pt-archiver --sleep conflicts with bulk operations
* Fixed bug 903443: pt-deadlock-logger crashes on MySQL 5.5
* Fixed bug 941064: pt-deadlock-logger can't clear deadlocks on 5.5
* Fixed bug 952727: pt-diskstats shows incorrect wr_mb_s
* Fixed bug 994176: pt-diskstats --group-by=all --headers=scroll prints a header for every sample
* Fixed bug 894140: pt-duplicate-key-checker sometimes recreates a key it shouldn't
* Fixed bug 923896: pt-kill: uninitialized value causes script to exit
* Fixed bug 1003003: pt-online-schema-change uses different keys for chunking and triggers
* Fixed bug 1003315: pt-online-schema-change --dry-run always fails on table with foreign keys
* Fixed bug 1004551: pt-online-schema-change --no-swap-tables causes error
* Fixed bug 976108: pt-online-schema-change doesn't allow to disable foreign key checks
* Fixed bug 976109: pt-online-schema-change doesn't handle column renames
* Fixed bug 988036: pt-online-schema-change causes deadlocks under heavy write load
* Fixed bug 989227: pt-online-schema-change crashes with PTDEBUG
* Fixed bug 994002: pt-online-schema-change 2.1.1 doesn't choose the PRIMARY KEY
* Fixed bug 994010: pt-online-schema-change 2.1.1 crashes without InnoDB
* Fixed bug 996915: pt-online-schema-change crashes with invalid --max-load and --critical-load
* Fixed bug 998831: pt-online-schema-change -- Should have an option to NOT drop tables on failure
* Fixed bug 1002448: pt-online-schema-change: typo for finding usable indexes
* Fixed bug 885382: pt-query-digest --embedded-attributes doesn't check cardinality
* Fixed bug 888114: pt-query-digest report crashes with infinite loop
* Fixed bug 949630: pt-query-digest mentions a Subversion repository
* Fixed bug 844034: pt-show-grants --separate fails with proxy user
* Fixed bug 946707: pt-sift loses STDIN after pt-diskstats
* Fixed bug 994947: pt-stalk doesn't reset cycles_true after collection
* Fixed bug 986151: pt-stalk-has mktemp error
* Fixed bug 993436: pt-summary Memory: Total reports M instead of G
* Fixed bug 1008778: pt-table-checksum doesn't wait for checksum table to replicate
* Fixed bug 1010232: pt-table-checksum doesn't check the size of checksum chunks
* Fixed bug 1011738: pt-table-checksum SKIPPED is zero but chunks were skipped
* Fixed bug 919499: pt-table-checksum fails with binary log error in mysql >= 5.5.18
* Fixed bug 972399: pt-table-checksum docs are not rendered right
* Fixed bug 978432: pt-table-checksum ignoring primary key
* Fixed bug 995274: pt-table-checksum can't use an undefined value as an ARRAY reference at line 2206
* Fixed bug 996110: pt-table-checksum crashes if InnoDB is disabled
* Fixed bug 987393: pt-table-checksum: Empy tables cause "undefined value as an ARRAY" errors
* Fixed bug 1002365: pt-table-sync --ignore-* options don't work with --replicate
* Fixed bug 1003014: pt-table-sync --replicate and --sync-to-master error "index does not exist"
* Fixed bug 823403: pt-table-sync --lock-and-rename doesn't work on 5.1
* Fixed bug 898138: pt-variable-advisor doesn't recognize 5.5.3+ concurrent_insert values

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
