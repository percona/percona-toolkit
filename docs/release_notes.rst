Release Notes
*************

v2.1.9 released 2013-02-14
==========================

Percona Toolkit 2.1.9 has been released.  This release primarily aims to
restore backwards-compatibility with pt-heartbeat 2.1.7 and older, but it
also has important bug fixes for other tools.

* Fixed bug 1103221: pt-heartbeat 2.1.8 doesn't use precision/sub-second timestamps
* Fixed bug 1099665: pt-heartbeat 2.1.8 reports big time drift with UTC_TIMESTAMP

The previous release switched the time authority from Perl to MySQL, and from
local time to UTC. Unfortunately, these changes caused a loss of precision and,
if mixing versions of pt-heartbeat, made the tool report a huge amount of
replication lag.  This release makes the tool compatible with pt-heartbeat
2.1.7 and older again, but the UTC behavior introduced in 2.1.8 is now only
available by specifying the new --utc option.

* Fixed bug  918056: pt-table-sync false-positive error "Cannot nibble table because MySQL chose no index instead of the PRIMARY index"

This is an important bug fix for pt-table-sync: certain chunks from
pt-table-checksum resulted in an impossible WHERE, causing the false-positive
"Cannot nibble" error, if those chunks had diffs.

* Fixed bug 1099836: pt-online-schema-change fails with "Duplicate entry" on MariaDB

MariaDB 5.5.28 (https://kb.askmonty.org/en/mariadb-5528-changelog/) fixed
a bug: "Added warnings for duplicate key errors when using INSERT IGNORE".
However, standard MySQL does not warn in this case, despite the docs saying
that it should.  Since pt-online-schema-change has always intended to ignore
duplicate entry errors by using "INSERT IGNORE", it now handles the MariaDB
case by also ignoring duplicate entry errors in the code.

* Fixed bug 1103672: pt-online-schema-change makes bad DELETE trigger if PK is re-created with new columns

pt-online-schema-change 2.1.9 handles another case of changing the primary key.
However, since changing the primary key is tricky, the tool stops if --alter
contains "DROP PRIMARY KEY", and you have to specify --no-check-alter to
acknowledge this case.

* Fixed bug 1099933: pt-stalk is too verbose, fills up log

Previously, pt-stalk printed a line for every check.  Since the tool is
designed to be a long-running daemon, this could result in huge log files
with "matched=no" lines. The tool has a new --verbose option which makes it
quieter by default.

All users should upgrade, but in particular, users of versions 2.1.7 and
older are strongly recommended to skip 2.1.8 and go directly to 2.1.9.

Users of pt-heartbeat in 2.1.8 who prefer the UTC behavior should keep in
mind that they will have to use the --utc option after upgrading.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/ or the Percona Software
Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Fixed bug 1103221: pt-heartbeat 2.1.8 doesn't use precision/sub-second timestamps
* Fixed bug 1099665: pt-heartbeat 2.1.8 reports big time drift with UTC_TIMESTAMP
* Fixed bug 1099836: pt-online-schema-change fails with "Duplicate entry" on MariaDB
* Fixed bug 1103672: pt-online-schema-change makes bad DELETE trigger if PK is re-created with new columns
* Fixed bug 1115333: pt-pmp doesn't list the origin lib for each function
* Fixed bug  823411: pt-query-digest shouldn't print "Error: none" for tcpdump
* Fixed bug 1103045: pt-query-digest fails to parse non-SQL errors
* Fixed bug 1105077: pt-table-checksum: Confusing error message with binlog_format ROW or MIXED on slave
* Fixed bug  918056: pt-table-sync false-positive error "Cannot nibble table because MySQL chose no index instead of the PRIMARY index"
* Fixed bug 1099933: pt-stalk is too verbose, fills up log

v2.1.8 released 2012-12-21
==========================

Percona Toolkit 2.1.8 has been released.  This release includes 28 bug fixes, beta support for MySQL 5.6, and extensive support for Percona XtraDB Cluster (PXC).  Users intending on running the tools on Percona XtraDB Cluster or MySQL 5.6 should upgrade.  The following tools have been verified to work on PXC versions 5.5.28 and newer:

* pt-table-chcecksum
* pt-online-schema-change
* pt-archive
* pt-mysql-summary
* pt-heartbeat
* pt-variable-advisor
* pt-config-diff
* pt-deadlock-logger

However, there are limitations when running these tools on PXC; see the Percona XtraDB Cluster section in each tool's documentation for further details.  All other tools, with the exception of pt-slave-find, pt-slave-delay and pt-slave-restart, should also work correctly, but in some cases they have not been modified to take advantage of PXC features, so they may behave differently in future releases.

The bug fixes are widely assorted.  The following highlights some of the more interesting and "hot" bugs:

* Fixed bug 1082599: pt-query-digest fails to parse timestamp with no query

Slow logs which include timestamps but no query--which can happen if using slow_query_log_timestamp_always in Percona Server--were misparsed, resulting in an erroneous report.  Now such no-query events show up in reports as ``/* No query */``.

* Fixed bug 1078838: pt-query-digest doesn't parse general log with "Connect user as user"

The "as" was misparsed and the following word would end up reported as the database; pt-query-digest now handles this correctly.

* Fixed bug 1015590: pt-mysql-summary doesn't handle renamed variables in Percona Server 5.5

Some renamed variables had caused the Percona Server section to work unreliably.

* Fixed bug 1074179:  pt-table-checksum doesn't ignore tables for --replicate-check-only

When using --replicate-check-only, filter options like --databases and --tables were not applied.

* Fixed bug 886059: pt-heartbeat handles timezones inconsistently

Previously, pt-heartbeat respected the MySQL time zone, but this caused false readings (e.g. very high lag) with slaves running in different time zones.  Now pt-heartbeat uses UTC regardless of the server or MySQL time zone.

* Fixed bug 1079341: pt-online-schema-change checks for foreign keys on MyISAM tables

Since MyISAM tables can't have foreign keys, and the tool uses the information_schema to find child tables, this could cause unnecessary load on the server.

2.1.8 continues the trend of solid bug fix releases, and all 2.1 users are encouraged to upgrade.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Beta support for MySQL 5.6
* Beta support for Percona XtraDB Cluster
* pt-online-schema-change: If ran on Percona XtraDB Cluster, requires PXC 5.5.28 or newer
* pt-table-checksum: If ran on Percona XtraDB Cluster, requires PXC 5.5.28 or newer
* pt-upgrade: Added --[no]disable-query-cache
* Fixed bug  927955: Bad pod2rst transformation
* Fixed bug  898665: Bad online docs formatting for --[no]vars
* Fixed bug 1022622: pt-config-diff is case-sensitive
* Fixed bug 1007938: pt-config-diff doesn't handle end-of-line comments
* Fixed bug  917770: pt-config-diff Use of uninitialized value in substitution (s///) at line 1996
* Fixed bug 1082104: pt-deadlock-logger doesn't handle usernames with dashes
* Fixed bug  886059: pt-heartbeat handles timezones inconsistently
* Fixed bug 1086259: pt-kill --log-dsn timestamp is wrong
* Fixed bug 1015590: pt-mysql-summary doesn't handle renamed variables in Percona Server 5.5
* Fixed bug 1079341: pt-online-schema-change checks for foreign keys on MyISAM tables
* Fixed bug  823431: pt-query-advisor hangs on big queries
* Fixed bug  996069: pt-query-advisor RES.001 is incorrect
* Fixed bug  933465: pt-query-advisor false positive on RES.001
* Fixed bug  937234: pt-query-advisor issues wrong RES.001
* Fixed bug 1082599: pt-query-digest fails to parse timestamp with no query
* Fixed bug 1078838: pt-query-digest doesn't parse general log with "Connect user as user"
* Fixed bug  957442: pt-query-digest with custom --group-by throws error
* Fixed bug  887638: pt-query-digest prints negative byte offset
* Fixed bug  831525: pt-query-digest help output mangled
* Fixed bug  932614: pt-slave-restart CHANGE MASTER query causes error
* Fixed bug 1046440: pt-stalk purge_samples slows down checks
* Fixed bug  986847: pt-stalk does not report NFS iostat
* Fixed bug 1074179: pt-table-checksum doesn't ignore tables for --replicate-check-only
* Fixed bug  911385: pt-table-checksum v2 fails when --resume + --ignore-database is used
* Fixed bug 1041391: pt-table-checksum debug statement for "Chosen hash func" prints undef
* Fixed bug 1075638: pt-table-checksum Illegal division by zero at line 7950
* Fixed bug 1052475: pt-table-checksum uninitialized value in numeric lt (<) at line 8611
* Fixed bug 1078887: Tools let --set-vars clobber the required SQL mode

v2.1.7 released 2012-11-19
==========================

Percona Toolkit 2.1.7 has been released which is a hotfix for two bugs when using pt-table-checksum with Percona XtraDB Cluster:

* Bug 1080384: pt-table-checksum 2.1.6 crashes using PTDEBUG
* Bug 1080385: pt-table-checksum 2.1.6 --check-binlog-format doesn't ignore PXC nodes

If you're using pt-table-checksum with a Percona XtraDB Cluster, you should upgrade.  Otherwise, users can wait until the next full release.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Fixed bug 1080384: pt-table-checksum 2.1.6 crashes using PTDEBUG
* Fixed bug 1080385: pt-table-checksum 2.1.6 --check-binlog-format doesn't ignore PXC nodes

v2.1.6 released 2012-11-13
==========================

Percona Toolkit 2.1.6 has been released.  This release includes 33 bug fixes and three new features: pt-online-schema-change now handles renaming columns without losing data, removing one of the tool's limitations.  pt-online-schema-change also got two new options: --default-engine and --statistics.  Finally, pt-stalk now has a plugin hook interface, available through the --plugin option.  The bug fixes are widely assorted.  The following highlights some of the more interesting and "hot" bugs:

* Bug 978133: pt-query-digest review table privilege checks don't work

The same checks were removed from pt-table-checksum on 2.1.3 and pt-table-sync on 2.1.4, so this just follows suit.

* Bug 938068: pt-table-checksum doesn't warn if binlog_format=row or mixed on slaves

A particularly important fix, as it may stop pt-table-checksum from breaking replication in these setups.

* Bug 1043438: pt-table-checksum doesn't honor --run-time while checking replication lag

If you run multiple instances of pt-table-checksum on a badly lagged server, actually respecting --run-time stops the instances from divebombing the server when the replica catches up.

* Bug 1062324: pt-online-schema-change DELETE trigger fails when altering primary key

Fixed by choosing a key on the new table for the DELETE trigger.

* Bug 1062563: pt-table-checksum 2.1.4 doesn't detect diffs on Percona XtraDB Cluster nodes

A follow up to the same fix in the previous release, this adds to warnings for cases in which pt-table-checksum may work incorrectly and require some user intervention: One for the case of master -> cluster, and one for cluster1 -> cluster2.

* Bug 821715: LOAD DATA LOCAL INFILE broken in some platforms

This bug has hounded the toolkit for quite some time. In some platforms, trying to use LOAD DATA LOCAL INFILE would fail as if the user didn't have enough privileges to perform the operation.  This was a misdiagnoses from MySQL; The actual problem was that the libmysqlclient.so provided by some vendors was compiled in a way that disallowed users from using the statement without some extra work.  This fix adds an 'L' option to the DSNs the toolkit uses, tells the the tools to explicitly enables LOAD DATA LOCAL INFILE.  This affected two pt-archiver and pt-upgrade, so if you are on an effected OS and need to use those, you can simply tag an L=1 to your DSN and everything should start working.

* Bug 866075: pt-show-grant doesn't support column-level grants

This was actually the 'hottest' bug in the tracker.

This is another solid bug fix release, and all 2.1 users are encouraged to upgrade.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* pt-online-schema-change: Columns can now be renamed without data loss
* pt-online-schema-change: New --default-engine option
* pt-stalk: Plugin hooks available through the --plugin option to extend the tool's functionality
* Fixed bug 1069951: --version-check default should be explicitly "off"
* Fixed bug 821715: LOAD DATA LOCAL INFILE broken in some platforms
* Fixed bug 995896: Useless use of cat in Daemon.pm
* Fixed bug 1039074: Tools exit 0 on error parsing options, should exit non-zero
* Fixed bug 938068: pt-table-checksum doesn't warn if binlog_format=row or mixed on slaves
* Fixed bug 1009510: pt-table-checksum breaks replication if a slave table is missing or different
* Fixed bug 1043438: pt-table-checksum doesn't honor --run-time while checking replication lag
* Fixed bug 1073532: pt-table-checksum error: Use of uninitialized value in int at line 2778
* Fixed bug 1016131: pt-table-checksum can crash with --columns if none match
* Fixed bug 1039569: pt-table-checksum dies if creating the --replicate table fails
* Fixed bug 1059732: pt-table-checksum doesn't test all hash functions
* Fixed bug 1062563: pt-table-checksum 2.1.4 doesn't detect diffs on Percona XtraDB Cluster nodes
* Fixed bug 1043528: pt-deadlock-logger can't parse db/tbl/index on partitioned tables
* Fixed bug 1062324: pt-online-schema-change DELETE trigger fails when altering primary key
* Fixed bug 1058285: pt-online-schema-change fails if sql_mode explicitly or implicitly uses ANSI_QUOTES
* Fixed bug 1073996: pt-online-schema-change fails with "I need a max_rows argument"
* Fixed bug 1039541: pt-online-schema-change --quiet doesn't disable --progress
* Fixed bug 1045317: pt-online-schema-change doesn't report how many warnings it suppressed
* Fixed bug 1060774: pt-upgrade fails if select column > 64 chars
* Fixed bug 1070916: pt-mysql-summary may report the wrong cnf file
* Fixed bug 903229: pt-mysql-summary incorrectly categorizes databases
* Fixed bug 866075: pt-show-grant doesn't support column-level grants
* Fixed bug 978133: pt-query-digest review table privilege checks don't work
* Fixed bug 956981: pt-query-digest docs for event attributes link to defunct Maatkit wiki
* Fixed bug 1047335: pt-duplicate-key-checker fails when it encounters a crashed table
* Fixed bug 1047701: pt-stalk deletes non-empty files
* Fixed bug 1070434: pt-stalk --no-stalk and --iterations 1 don't wait for the collect
* Fixed bug 1052722: pt-fifo-split is processing n-1 rows initially
* Fixed bug 1013407: pt-find documentation error with mtime and InnoDB
* Fixed bug 1059757: pt-trend output has no header
* Fixed bug 1063933: pt-visual-explain docs link to missing pdf
* Fixed bug 1075773: pt-fk-error-logger crashes if there's no foreign key error
* Fixed bug 1075775: pt-fk-error-logger --dest table example doesn't work

v2.1.5 released 2012-10-08
==========================

Percona Toolkit 2.1.5 has been released.  This release is less than two weeks after the release of 2.1.4 because we wanted to address these bugs quickly:

* Bug 1062563: pt-table-checksum 2.1.4 doesn't detect diffs on Percona XtraDB Cluster nodes

* Bug 1063912: pt-table-checksum 2.1.4 miscategorizes Percona XtraDB Cluster-based slaves as cluster nodes

* Bug 1064016: pt-table-sync 2.1.4 --version-check may not work with HTTPS/SSL

The first two bugs fix how pt-table-checksum works with Percona XtraDB Cluster (PXC).  Although the 2.1.4 release did introduce support for PXC, these bugs prevented pt-table-checksum from working correctly with a cluster.

The third bug is also related to a feature new in 2.1.4: --version-check.  The feature uses HTTPS/SSL by default, but some modules in pt-table-sync weren't update which could prevent it from working on older systems.  Related, the version check web page mentioned in tools' documentation was also created.

If you're using pt-table-checksum with a Percona XtraDB Cluster, you should definitely upgrade.  Otherwise, users can wait until 2.1.6 for another full release.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Fixed bug 1062563: pt-table-checksum 2.1.4 doesn't detect diffs on Percona XtraDB Cluster nodes
* Fixed bug 1063912: pt-table-checksum 2.1.4 miscategorizes Percona XtraDB Cluster-based slaves as cluster nodes
* Fixed bug 1064016: pt-table-sync 2.1.4 --version-check may not work with HTTPS/SSL
* Fixed bug 1060423: Missing version-check page

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
