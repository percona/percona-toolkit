Release Notes
*************

v3.0.3 released 2017-05-18
==========================

Percona Toolkit 3.0.3 includes the following changes:

New Features

* Added the ``--skip-check-slave-lag`` option for ``pt-table-checksum``, ``pt-online-schema-change``, and ``pt-archiver``.

  This option can be used to specify list of servers where to skip checking for slave lag.

* 1642754: Added support for collecting replication slave information in ``pt-stalk``.

* PT-111: Added support for collecting information about variables from Performance Schema in ``pt-stalk``. For more information, see 1642753.

* PT-116: Added the ``--[no]use-insert-ignore`` option for ``pt-online-schema-change`` to force or prevent using ``IGNORE`` on ``INSERT`` statements. For more information, see 1545129.

Bug Fixes

* PT-115: Fixed ``OptionParser`` to accept repeatable DSNs.

* PT-126: Fixed ``pt-online-schema-change`` to correctly parse comments. For more information, see 1592072.

* PT-128: Fixed ``pt-stalk`` to include memory usage information. For more information, see 1510809.

* PT-130: Fixed ``pt-mext`` to work with non-empty RSA public key. For more information, see 1587404.

* PT-132: Fixed ``pt-online-schema-change`` to enable ``--no-drop-new-table`` when ``--no-swap-tables`` and ``--no-drop-triggers`` are used.

Changelog
---------


v3.0.2 released 2017-03-27
==========================

Percona Toolkit 3.0.2 includes the following changes:

New Features

* PT-73: Added support for SSL connections to ``pt-mongodb-summary`` and ``pt-mongodb-query-digest``

* 1642751: Enabled gathering of information about locks and transactions by ``pt-stalk`` using Performance Schema if it is enabled (Thanks Agustin Gallego)

Bug Fixes

* PT-74: Fixed gathering of security settings when running ``pt-mongodb-summary`` on a mongod instance that is specified as the host

* PT-75: Changed the default sort order in ``pt-mongodb-query-digest`` output to descending

* PT-76: Added support of ``&`` and ``#`` symbols in passwords for ``pt-mysql-summary``

* PT-77: Updated ``Makefile`` to support new MongoDB tools

* PT-89: Fixed ``pt-stalk`` to run ``top`` more than once to collect useful CPU usage

* PT-93: Fixed ``pt-mongodb-query-digest`` to make query ID match query key (Thanks Kamil Dziedzic)

* PT-94: Fixed ``pt-online-schema-change`` to not make duplicate rows in ``_t_new`` when updating primary key. Also see 1646713.

* PT-101: Fixed ``pt-table-checksum`` to correctly use the ``--slave-user`` and ``--slave-password`` options. Also see 1651002.

* PT-105: Fixed ``pt-table-checksum`` to continue running if a database is dropped in the process

v3.0.1 released 2017-02-20
==========================

Percona Toolkit 3.0.1 GA includes the following changes:

* Added requirement to run ``pt-mongodb-summary`` as a user with the ``clusterAdmin`` or ``root`` built-in roles.

v3.0 released 2017-02-06
========================

Percona Toolkit 3.0.0 RC includes the following changes:

New Features

* Added ``pt-mongodb-summary`` tool

* Added ``pt-mongodb-query-digest`` tool

Bug fixes

* 1402776: Updated ``MySQLProtocolParser`` to fix error when parsing ``tcpdump`` capture with ``pt-query-digest``

* 1632522: Fixed failure of ``pt-online-schema-change`` when altering a table with a self-referencing foreign key (Thanks Amiel Marqeta)

* 1654668: Fixed failure of ``pt-summary`` on Red Hat and derivatives (Thanks Marcelo Altmann)


v2.2.20 released 2016-12-09
===========================

Percona Toolkit 2.2.20 includes the following changes:

New Features

* 1636068: New ``--pause-file`` option has been implemented for ``pt-online-schema-change``. When used ``pt-online-schema-change`` will pause while the specified file exists.

* 1638293 and 1642364: ``pt-online-schema-change`` now supports adding and removing the ``DATA DIRECTORY`` to a new table with the ``--data-dir`` and ``--remove-data-dir`` options.

* 1642994: Following schemas/tables have been added to the default ignore list: ``mysql.gtid_execution``, ``sys.sys_config``, ``mysql.proc``, ``mysql.inventory``, ``mysql.plugin``, ``percona.*`` (including checksums, dsns table), ``test.*``, and ``percona_schema.*``.

* 1643940: ``pt-summary`` now provides information about Transparent huge pages. 

* 1604834: New ``--preserve-embedded-numbers`` option has been implemented for ``pt-query-digest`` which can be used to preserve numbers in database/table names when fingerprinting queries.

Bug Fixes

* 1613915: ``pt-online-schema-change`` could miss the data due to the way ENUM values are sorted.

* 1625005: ``pt-online-schema-change`` didn't apply underscores to foreign keys individually.
  
* 1566556: ``pt-show-grants`` didn't work correctly with *MariaDB* 10 (*Daniël van Eeden*).

* 1634900: ``pt-upgrade`` would fail when log contained ``SELECT...INTO`` queries.

* 1639052: ``pt-table-checksum`` now automatically excludes checking schemas named ``percona`` and ``percona_schema`` which aren't consistent across the replication hierarchy.

* 1635734: ``pt-slave-restart --config`` did not recognize ``=`` as a separator.

* 1362942: ``pt-slave-restart`` would fail on *MariaDB* 10.0.13.

Changelog
---------

* Fixed bug 1362942: pt-slave-restart fails on MariaDB 10.0.13 (gtid_mode confusion)
* Fixed bug 1566556: pt-show-grants fails against MariaDB10+    
* Feature    1604834: pt-query-digest numbers in table or column names converted to question marks (--preserve-embedded-numbers)
* Fixed bug 1613915: pt-online-schema-change misses data.  Fixed sort order for ENUM fields 
* Fixed bug 1625005: pt-online-schema-change doesn't apply underscores to foreign keys individually
* Fixed bug 1634900: pt-upgrade fails with SELECT INTO 
* Fixed bug 1635734: pt-slave-restart --config does not recognize = as separator 
* Feature   1636068: Added pause to NibbleIterator
* Feature   1638293: --data-dir parameter in order to create the table on a different partition
* Feature   1639052: with pt-table-checksum automatically exclude checking schemas named percona, percona_schema     
* Feature   1642364: pt-online-schema-change Added --remove-data-dir feature
* Feature   1643914: Fixed several typos in the doc (Thanks Dario Minnucci)
* Feature   1643940: Add Transparent huge pages info to pt-summary
* Feature   1643941: Add Memory management library to pt-mysql-summary 

v2.2.19 released 2016-08-16
===========================

Percona Toolkit 2.2.19 includes the following changes:

New Features

* 1221372: ``pt-online-schema-change`` now aborts with an error if the server is a slave, because this can break data consistency in case of row-based replication. If you are sure that the slave will not use row-based replication, you can disable this check using the ``--force-slave-run`` option.

* 1485195: ``pt-table-checksum`` now forces replica table character set to UTF-8.

* 1517155: Added ``--create-table-engine`` option to ``pt-heartbeat``, which can be used to set a storage engine for the ``heartbeat`` table different from the database default engine.

* 1595678: Added ``--slave-user`` and ``--slave-password`` options to ``pt-online-schema-change``

* 1595912: Added ``--slave-user`` and ``--slave-password`` options to ``pt-table-sync`` and ``pt-table-checksum``

* 1610385: ``pt-online-schema-change`` now re-checks the list of slaves in the DSN table. This enables changing the contents of the table while the tool is running.


Bug fixes

* 1581752: Fixed ``pt-query-digest`` date and time parsing from MySQL 5.7 slow query log.

* 1592166: Fixed memory leak when ``pt-kill`` kills a query

* 1592608: Fixed overflow of ``CONCAT_WS`` when ``pt-table-checksum`` or ``pt-table-sync`` checksums large BLOB, TEXT, or BINARY columns.

* 1593265: Fixed ``pt-archiver`` deleting rows that were not archived.

* 1610386: Fixed ``pt-slave-restart`` handling of GTID ranges where the left-side integer is larger than 9

* 1610387: Removed extra word 'default' from the ``--verbose`` help for ``pt-slave-restart``

* 1610388: Fixed ``pt-table-sync`` not quoting enum values properly. They are now recognized as CHAR fields.

Changelog
---------

* Feature 1610385: Recheck the list of slaves while OSC runs (Thanks Daniël van Eeden & Mikhail Izioumtchenko)
* Fixed bug 1221372: pt-osc should error if server is a slave in row based replication
* Fixed bug 1485195: pt-table-checksum should force replica table charset to utf8 Edit (Thanks Jaime Crespo)
* Fixed bug 1517155: Added --create-table-engine param to pt-heartbeat
* Fixed bug 1581752: SlowLogParser is able to handle dates in RFC339 format for MySQL 5.7 (Thanks Nickolay Ihalainen)
* Fixed bug 1592166: pt-kill leaks memory
* Fixed bug 1592166: pt-kill leaks memory each time it kills a query
* Fixed bug 1592608: Large BLOB/TEXT/BINARY Produces NULL Checksum (Thanks Jervin Real)
* Fixed bug 1593265: Fixed pt-archiver deletes wrong rows #103 (Thanks Tibor Korocz & David Ducos)
* Fixed bug 1595678: Added --slave-user and --slave-password to pt-online-schema-change & pt-table-sync
* Fixed bug 1610386: Handle GTID ranges where the left-side integer is larger than 9 (Thanks @sodabrew)
* Fixed bug 1610387: Remove extra word 'default' from the --verbose help (Thanks @sodabrew)
* Fixed bug 1610388: add enum column type to is_char check so that values are properly quoted (Thanks Daniel Kinon)

v2.2.18 released 2016-06-24
===========================

Percona Toolkit 2.2.18 has been released. This release includes the following new features and bug fixes.

New features:

* 1537416: ``pt-stalk`` now sorts the output of transactions by id

* 1553340: Added "Shared" memory info to ``pt-summary``

* PT-24: Added the ``--no-vertical-format`` option for ``pt-query-digest``, allowing compatibility with non-standard MySQL clients that don't support the ``\G`` directive at the end of a statement
  
Bug fixes:

* 1402776: Fixed error when parsing ``tcpdump`` capture with ``pt-query-digest``

* 1521880: Improved ``pt-online-schema-change`` plugin documentation

* 1547225: Clarified the description of the ``--attribute-value-limit`` option for ``pt-query-digest``

* 1569564: Fixed all PERL-based tools to return a zero exit status when run with the ``--version`` option

* 1576036: Fixed error that sometimes prevented to choose the primary key as index, when using the ``-where`` option for ``pt-table-checksum``

* 1585412: Fixed the inability of ``pt-query-digest`` to parse the general log generated by MySQL (and Percona Server) 5.7 instance

* PT-36: Clarified the description of the ``--verbose`` option for ``pt-slave-restart``


Changelog
---------

* Feature 1537416  :  pt-stalk now sorts the output of transactions by id
* Feature 1553340  :  Added "Shared" memory info to pt-summary
* Feature PT-24    :  Added the --no-vertical-format option for pt-query-digest, allowing compatibility with non-standard MySQL clients that don't support the \G directive at the end of a statement
* Fixed bug 1402776:  Fixed error when parsing tcpdump capture with pt-query-digest
* Fixed bug 1521880:  Improved pt-online-schema-change plugin documentation
* Fixed bug 1547225:  Clarified the description of the --attribute-value-limit option for pt-query-digest
* Fixed bug 1569564:  Fixed all PERL-based tools to return a zero exit status when run with the --version option
* Fixed bug 1576036:  Fixed error that sometimes prevented to choose the primary key as index, when using the -where option for pt-table-checksum
* Fixed bug 1585412:  Fixed the inability of pt-query-digest to parse the general log generated by MySQL (and Percona Server) 5.7 instance
* Fixed bug PT-36  :  Clarified the description of the --verbose option for pt-slave-restart

v2.2.17 released 2016-03-07
===========================

Percona Toolkit 2.2.17 has been released. This release contains 1 new feature and 15 bug fixes.

New Features:

* Percona Toolkit 2.2.17 has implemented general compatibility with MySQL 5.7 tools, documentation and test suite

Bug Fixes:

* Bug 1523685: ``pt-online-schema-change`` invalid recursion method where comma was interpreted as the separation of two DSN methods has been fixed.

* Bugs 1480719 and 1536305: The current version of Perl on supported distributions has implemented stricter checks for arguments provided to ``sprintf``. This could cause warnings when ``pt-query-digest`` and ``pt-table-checksum`` were being run.

* Bug 1498128: ``pt-online-schema-change`` would fail with an error if the table being altered has foreign key constraints where some start with an underscore and some don't.

* Bug 1336734: ``pt-online-schema-change`` has implemented new ``--null-to-non-null`` flag which can be used to convert ``NULL`` columns to ``NOT NULL``.

* Bug 1362942: ``pt-slave-restart`` would fail to run on |MariaDB| 10.0.13 due to a different implementation of ``GTID``.

* Bug 1389041: ``pt-table-checksum`` had a high likelihood to skip a table when row count was around ``chunk-size`` * ``chunk-size-limit``. To address this issue a new ``--slave-skip-tolerance`` option has been implemented.

* Bug 1506748: ``pt-online-schema-change`` could not set the ``SQL_MODE`` by using the ``--set-vars`` option, preventing some use case schema changes that require it.

* Bug 1523730: ``pt-show-grants`` didn't sort the column-level privileges.

* Bug 1526105: ``pt-online-schema-change`` would fail if used with ``--no-drop-old-table`` option after ten times. The issue would arise because there was an accumulation of tables that have already have had their names extended, the code would retry ten times to append an underscore, each time finding an old table with that number of underscores appended.

* Bug 1529411: ``pt-mysql-summary`` was displaying incorrect information about Fast Server Restarts for Percona Server 5.6.

* PT-30: ``pt-stalk`` shell ``collect`` module was confusing the new mysql variable ``binlog_error_action`` with the ``log_error`` variable.

Changelog
---------

* Feature          :  General compatibility with MySQL 5.7 tools, docs and test suite
* Fixed bug 1529411:  pt-mysql-summary displays incorrect info about Fast Server Restarts for Percona Server 5.6
* Fixed bug 1506748:  pt-online-schema-change cannot set sql_mode using --set-vars
* Fixed bug 1336734:  pt-online-schema-change added --null-to-non-null option to allow NULLable columns to be converted to NOT NULL
* Fixed bug 1498128:  pt-online-schema-change doesn't apply underscores to foreign keys individually
* Fixed bug 1523685:  pt-online-schema Invalid recursion method: t=dsns
* Fixed bug 1526105:  pt-online-schema-change fails when using --no-drop-old-table after 10 times
* Fixed bug 1536305:  pt-query-digest : Redundant argument in sprintf
* Fixed bug PT-27  :  pt-query-digest doc bug with --since and too many colons
* Fixed bug PT-28  :  pt-query-digest: Make documentation of --attribute-value-limit option more clear
* Fixed bug 1435370:  pt-show-grants fails against MySQL-5.7.6
* Fixed bug 1523730:  pt-show-grants doesn't sort column-level privileges
* Fixed bug 1362942:  pt-slave-restart fails on MariaDB 10.0.13 (gtid_mode confusion)
* Fixed bug PT-30  :  pt-stalk: new var binlog_error_action causes bug in collect module
* Fixed bug 1389041:  pt-table-checksum has high likelyhood to skip a table when row count is around chunk-size * chunk-size-limit
* Fixed bug 1480719:  pt-table-checksum redundant argument in printf

v2.2.16 released 2015-11-09
===========================

Percona Toolkit 2.2.16 has been released. This release contains 3 new features and 2 bug fixes.

New Features:

* 1491261: When using MySQL 5.6 or later, and ``innodb_stats_persistent`` option is enabled (by default, it is enabled), then ``pt-online-schema-change`` will now run with the ``--analyze-before-swap`` option. This ensures that queries continue to use correct execution path, instead of switching to full table scan, which could cause possible downtime. If you do not want ``pt-online-schema-change`` to run ``ANALYZE`` on new tables before the swap, you can disable this behavior using the ``--no-analyze-before-swap`` option.

* 1402051: ``pt-online-schema-change`` will now wait forever for slaves to be available and not be lagging. This ensures that the tool does not abort during faults and connection problems on slaves.

* 1452895: ``pt-archiver`` now issues ‘keepalive’ queries during and after bulk insert/delete process that takes a long time. This keeps the connection alive even if the ``innodb_kill_idle_transaction`` variable is set to a low value.

Bug Fixes:

* 1488685: The ``--filter`` option for ``pt-kill`` now works correctly.

* 1494082: The ``pt-stalk`` tool no longer uses the ``-warn`` option when running ``find``, because the option is not supported on FreeBSD.

Changelog
---------

* Fixed bug 1452895: pt-archiver dies with "MySQL server has gone away" when innodb_kill_idle_transaction set to low value and bulk insert/delete process takes too long time
* Fixed bug 1488685: pt-kill option --filter does not work
* Feature   1402051: pt-online-schema-change should reconnect to slaves
* Fixed bug 1491261: pt-online-schema-change, MySQL 5.6, and InnoDB optimizer stats can cause downtime
* Fixed bug 1494082: pt-stalk find -warn option is not portable
* Feature   1389041: Document that pt-table-checksum has high likelihood to skip a table when row count is around chunk-size * chunk-size-limit

v2.2.15 released 2015-08-28
===========================

**New Features**

* Added ``--max-flow-ctl`` option with a value set in percent. When a Percona XtraDB Cluster node is very loaded, it sends flow control signals to the other nodes to stop sending transactions in order to catch up. When the average value of time spent in this state (in percent) exceeds the maximum provided in the option, the tool pauses until it falls below again.

  Default is no flow control checking.

  This feature was requested in the following bugs: 1413101 and 1413137.

* Added the ``--sleep`` option for ``pt-online-schema-change`` to avoid performance problems. The option accepts float values in seconds.
  
  This feature was requested in the following bug: 1413140.

* Implemented ability to specify ``--check-slave-lag`` multiple times. The following example enables lag checks for two slaves:

  .. code-block:: console

   pt-archiver --no-delete --where '1=1' --source h=oltp_server,D=test,t=tbl --dest h=olap_server --check-slave-lag h=slave1 --check-slave-lag h=slave2 --limit 1000 --commit-each

  This feature was requested in the following bug: 14452911.

* Added the ``--rds`` option to ``pt-kill``, which makes the tool use Amazon RDS procedure calls instead of the standard MySQL ``kill`` command.
  
  This feature was requested in the following bug: 1470127.

**Bugs Fixed**

* 1042727: ``pt-table-checksum`` doesn't reconnect the slave $dbh
  
  Before, the tool would die if any slave connection was lost. Now the tool waits forever for slaves.

* 1056507: ``pt-archiver --check-slave-lag`` agressiveness
  
  The tool now checks replication lag every 100 rows instead of every row, which significantly improves efficiency.

* 1215587: Adding underscores to constraints when using ``pt-online-schema-change`` can create issues with constraint name length
  
  Before, multiple schema changes lead to underscores stacking up on the name of the constraint until it reached the 64 character limit. Now there is a limit of two underscores in the prefix, then the tool alternately removes or adds one underscore, attempting to make the name unique.

* 1277049: ``pt-online-schema-change`` can't connect with comma in password
  
  For all tools, documented that commas in passwords provided on the command line must be escaped.

* 1441928: Unlimited chunk size when using ``pt-online-schema-change`` with ``--chunk-size-limit=0`` inhibits checksumming of single-nibble tables
  
  When comparing table size with the slave table, the tool now ignores ``--chunk-size-limit`` if it is set to zero to avoid multiplying by zero.

* 1443763: Update documentation and/or implentation of ``pt-archiver --check-interval``
  
  Fixed the documentation for ``--check-interval`` to reflect its correct behavior.

* 1449226: ``pt-archiver`` dies with "MySQL server has gone away" when ``--innodb_kill_idle_transaction`` is set to a low value and ``--check-slave-lag`` is enabled
  
  The tool now sends a dummy SQL query to avoid timing out. 

* 1446928: ``pt-online-schema-change`` not reporting meaningful errors
  
  The tool now produces meaningful errors based on text from MySQL errors.

* 1450499: ReadKeyMini causes ``pt-online-schema-change`` session to lock under some circumstances
  
  Removed ReadKeyMini, because it is no longer necessary.

* 1452914: ``--purge`` and ``--no-delete`` are mutually exclusive, but still allowed to be specified together by ``pt-archiver``
  
  The tool now issues an error when ``--purge`` and ``--no-delete`` are specified together

* 1455486: ``pt-mysql-summary`` is missing the ``--ask-pass`` option
  
  Added the ``--ask-pass`` option to the tool

* 1457573: ``pt-sift`` fails to download ``pt-diskstats`` ``pt-pmp`` ``pt-mext`` ``pt-align``
  
  Added the ``-L`` option to ``curl`` and changed download address to use HTTPS.

* 1462904: ``pt-duplicate-key-checker`` doesn't support triple quote in column name
  
  Updated TableParser module to handle literal backticks.

* 1488600: ``pt-stalk`` doesn't check TokuDB status
  
  Implemented status collection similar to how it is performed for InnoDB.

* 1488611: various testing bugs related to newer perl versions
  
  Fixed test failures related to new Perl versions.

v2.2.14 released 2015-04-14
===========================

Percona Toolkit 2.2.14 has been released. This release contains two new features and seventeen bug fixes.

New Features:

* pt-slave-find can now resolve the IP address and show the slave's hostname. This can be done with the new ``--resolve-address`` option.  

* pt-table-sync can now ignore the tables whose names match specific Perl regex with the ``--ignore-tables-regex`` option.

Bugs Fixed:

* Fixed bug 925781: Inserting non-BMP characters into a column with utf8 charset would cause the ``Incorrect string value`` error when running the pt-table-checksum.

* Fixed bug 1368244: pt-online-schema-change ``--alter-foreign-keys-method=drop-swap`` was not atomic and thus it could be interrupted. Fixed by disabling common interrupt signals during the critical drop-rename phase.

* Fixed bug 1381280: pt-table-checksum was failing on ``BINARY`` field in Primary Key. Fixed by implementing new ``--binary-index`` flag to optionally create checksum table using BLOB data type.

* Fixed bug 1421405: Running pt-upgrade against a log with many identical (or similar) queries was producing repeated sections with the same fingerprint.

* Fixed bug 1402730: pt-duplicate-key-checker was not checking for duplicate keys when ``--verbose`` option was set.

* Fixed bug 1406390: A race condition was causing pt-heartbeat to crash with sleep argument error.

* Fixed bug 1417558: pt-stalk when used along with ``--collect-strace`` didn't write the strace output to the expected destination file.

* Fixed bug 1421025: Missing dependency for ``perl-TermReadKey`` RPM package was causing toolkit commands to fail when they were run with ``--ask-pass`` option. 

* Fixed bug 1421781: pt-upgrade would fail when log contained ``SELECT...INTO`` queries. Fixed by ignoring/skipping those queries.

* Fixed bug 1425478: pt-stalk was removing non-empty files that were starting with an empty line.

* Fixed bug 1419098: Fixed bad formatting in the pt-table-checksum documentation.

Changelog
---------

* Fixed bug 1402730  pt-duplicate-key-checker seems useless with MySQL 5.6
* Fixed bug 1415646  pt-duplicate-key-checker documentation does not explain how Size Duplicate Indexes is calculated
* Fixed bug 1406390  pt-heartbeat crashes with sleep argument error
* Fixed bug 1368244  pt-online-schema-change --alter-foreign-keys-method=drop-swap is not atomic
* FIxed bug 1417864  pt-online-schema-change documentation, the interpretation of --tries create_triggers:5:0.5,drop_triggers:5:0.5 is wrong
* Fixed bug 1404313  pt-query-digest: specifying a file that doesn't exist as log causes the tool to wait for STDIN instead of giving an error
* Feature   1418446  pt-slave-find resolve IP addresses option
* Fixed bug 1417558  pt-stalk with --collect-strace output doesn't go to an YYYY_MM_DD_HH_mm_ss-strace file
* Fixed bug 1425478  pt-stalk removes non-empty files that start with empty line
* Fixed bug 925781   pt-table-checksum checksum error when default-character-set = utf8
* Fixed bug 1381280  pt-table-checksum fails on BINARY field in PK
* Feature   1439842  pt-table-sync lacks --ignore-tables-regex option
* Fixed bug 1401399  pt-table-sync fails to close one db handle
* Fixed bug 1442277  pt-table-sync-ignores system databases but doc doesn't clarify this
* Fixed bug 1421781  pt-upgrade fails on SELECT ... INTO queries
* Fixed bug 1421405  pt-upgrade fails to aggregate queries based on fingerprint
* Fixed bug 1439348  pt-upgrade erroneously reports number of diffs
* Fixed bug 1421025  rpm missing dependency on perl-TermReadKey for --ask-pass

v2.2.13 released 2015-01-26
===========================

Percona Toolkit 2.2.13 has been released. This release contains one new feature and twelve bug fixes.

New Features:

* pt-kill now supports new ``--query-id`` option. This option can be used to print a query fingerprint hash after killing a query to enable the cross-referencing with the pt-query-digest output. This option can be used along with ``--print`` option as well.  

Bugs Fixed:

* Fixed bug 1019479: pt-table-checksum now works with ``ONLY_FULL_GROUP_BY`` sql_mode. 

* Fixed bug 1394934: running pt-table-checksum in debug mode would cause an error.

* Fixed bug 1396868: regression introduced in Percona Toolkit 2.2.12 caused pt-online-schema-change not to honor ``--ask-pass`` option.

* Fixed bug 1399789: pt-table-checksum would fail to find Percona XtraDB Cluster nodes when variable ``wsrep_node_incoming_address`` was set to ``AUTO``.

* Fixed bug 1408375: Percona Toolkit was vulnerable to MITM attack which could allow exfiltration of MySQL configuration information via ``--version-check`` option. This vulnerability was logged as `CVE 2015-1027 <http://www.cve.mitre.org/cgi-bin/cvename.cgi?name=2015-1027>_`

* Fixed bug 1321297: pt-table-checksum was reporting differences on timestamp columns with replication from 5.5 to 5.6 server version, although the data was identical. 

* Fixed bug 1388870: pt-table-checksum was showing differences if the master and slave were in different time zone.  

* Fixed bug 1402668: pt-mysql-summary would exit if Percona XtraDB Cluster was in ``Donor/Desynced`` state.

* Fixed bug 1266869: pt-stalk would fail to start if ``$HOME`` environment variable was not set.

Changelog
---------

* Feature   1391240:  pt-kill added query fingerprint hash to output 
* Fixed bug 1402668:  pt-mysql-summary fails on cluster in Donor/Desynced status 
* Fixed bug 1396870:  pt-online-schema-change CTRL+C leaves terminal in inconsistent state 
* Fixed bug 1396868:	pt-online-schema-change --ask-pass option error
* Fixed bug 1266869:  pt-stalk fails to start if $HOME environment variable is not set 
* Fixed bug 1019479:	pt-table-checksum does not work with sql_mode ONLY_FULL_GROUP_BY
* Fixed bug 1394934:  pt-table-checksum error in debug mode
* Fixed bug 1321297:  pt-table-checksum reports diffs on timestamp columns in 5.5 vs 5.6 
* Fixed bug 1399789:	pt-table-checksum fails to find pxc nodes when wsrep_node_incoming_address is set to AUTO
* Fixed bug 1388870:  pt-table-checksum has some errors with different time zones
* Fixed bug 1408375:  vulnerable to MITM attack which would allow exfiltration of MySQL configuration information via --version-check
* Fixed bug 1404298:  missing MySQL5.7 test files for pt-table-checksum 
* Fixed bug 1403900:  added sandbox and fixed sakila test db for 5.7 

v2.2.12 released 2014-11-14
===========================

Percona Toolkit 2.2.12 has been released. This release contains one new feature and seven bug fixes.

New Features:

* pt-stalk now gathers ``dmesg`` output from up to 60 seconds before the triggering event. 

Bugs Fixed:

* Fixed bug 1376561: pt-archiver was not able to archive all the rows when a table had a hash partition. Fixed by implementing support for tables which have primary or unique indexes.

* Fixed bug 1217466: pt-table-checksum would refuses to run on Percona XtraDB Cluster if ``server_id`` was the same on all nodes. Fixed by using the ``wsrep_node_incoming_address`` as a unique identifier for cluster nodes, instead of relying on ``server_id``.

* Fixed bug 1269695: pt-online-schema-change documentation now contains more information about limitations on why it isn't running ``ALTER TABLE`` for a table which has only a non-unique index.

* Fixed bug 1328686: Running pt-hearbeat with --check-read-only option would cause an error when running on server with ``read_only`` option. Tool now waits for server ``read_only`` status to be disabled before starting to run.

* Fixed bug 1373937: pt-table-checksum now supports ``none`` as valid ``--recursion-method`` when using with Percona XtraDB Cluster. 

* Fixed bug 1377888: Documentation was stating that pt-query-digest is able to parse a raw binary log file, while it can only parse a file which was decoded with ``mysqlbinlog`` tool before. Fixed by improving the documentation and adding a check for binary file and providing a relevant error message.

Changelog
---------

* Fixed bug 1376561:	pt-archiver is not able to archive all the rows when a table has a hash partition
* Fixed bug 1328686:	pt-heartbeat check-read-only option does not prevent creates or inserts
* Fixed bug 1269695:	pt-online-schema-change does not allow ALTER for a table without a non-unique, while manual does not explain this
* Fixed bug 1217466:	pt-table-checksum refuses to run on PXC if server_id is the same on all nodes
* Fixed bug 1373937:	pt-table-checksum requires recursion when working with and XtraDB Cluster node
* Fixed bug 1377888:	pt-query-digest manual for --type binlog is ambiguous
* Fixed bug 1349086:	pt-stalk should also gather dmesg output 
* Fixed bug 1361293:	Some scripts fail when no-version-check option is put in global config file

v2.2.11 released 2014-09-26
===========================

Percona Toolkit 2.2.11 has been released. This release contains seven bug fixes.

Bugs Fixed:

* Fixed bug 1262456: pt-query-digest didn't report host details when host was using skip-name-resolve option. Fixed by using the IP of the host instead of it's name, when the hostname is missing.

* Fixed bug 1264580: pt-mysql-summary was incorrectly parsing key/value pairs in the wsrep_provider_options option, which resulted in incomplete my.cnf information.

* Fixed bug 1318985: pt-stalk is now using ``SQL_NO_CACHE`` when executing queries for locks and transactions. Previously this could lead to situations where most of the queries that were ``waiting on query cache mutex`` were the pt-stalk queries (INNODB_TRX).

* Fixed bug 1348679: When using ``-- -p`` option to enter the password for pt-stalk it would ask user to re-enter the password every time tool connects to the server to retrieve the information. New option ``--ask-pass`` has been introduced that can be used to specify the password only once.

* Fixed bug 1368379: A parsing error caused pt-summary ( specifically the ``report_system_info`` module) to choke on the "Memory Device" parameter named "Configured Clock Speed" when using dmidecode to report memory slot information.

Changelog
---------

* Fixed bug 1262456: pt-query-digest doesn't report host details
* Fixed bug 1264580: pt-mysql-summary incorrectly tries to parse key/value pairs in wsrep_provider_options resulting in incomplete my.cnf information
* Fixed bug 1318985: pt-stalk should use SQL_NO_CACHE
* Fixed bug 1348679: pt-stalk handles mysql user password in awkward way
* Fixed bug 1365085: Various issues with tests
* Fixed bug 1368379: pt-summary problem parsing dmidecode output on some machines
* Fixed bug 1303388: Typo in pt-variable-advisor

v2.2.10 released 2014-08-06
===========================

Percona Toolkit 2.2.10 has been released. This release contains six bug fixes.

Bugs Fixed:

* Fixed bug 1287253: pt-table-checksum would exit with error if it would encounter deadlock when doing checksum. This was fixed by retrying the command in case of deadlock error.

* Fixed bug 1311654: When used with Percona XtraDB Cluster, pt-table-checksum could show incorrect result if --resume option was used. This was fixed by adding a new ``--replicate-check-retries`` command line parameter. If you are having resume problems you can now set ``--replicate-check-retries`` N , where N is the number of times to retry a discrepant checksum (default = 1 , no retries). Setting a value of ``3`` is enough to completely eliminate spurious differences.

* Fixed bug 1299387: pt-query-digest didn't work correctly do to a changed logging format when field ``Thread_id`` has been renamed to ``Id``. Fixed by implementing support for the new format.

* Fixed bug 1340728: in some cases, where the index was of type "hash" , pt-online-schema-change would refuse to run because MySQL reported it would not use an index for the select. This check should have been able to be skipped using --nocheck-plan option, but it wasn't. ``--nocheck-plan`` now ignores the chosen index correctly.

* Fixed bug 1253872: When running pt-table-checksum or pt-online-schema on a server that is unused, setting the 20% max load would fail due to tools rounding the value down. This has been fixed by rounding the value up.

* Fixed bug 1340364: Due to incompatibility of dash and bash syntax some shell tools were showing error when queried for version.

Changelog
---------

* Fixed bug 1287253: pt-table-checksum deadlock 
* Fixed bug 1299387: 5.6 slow query log Thead_id becomes Id
* Fixed bug 1311654: pt-table-checksum + PXC inconsistent results upon --resume
* Fixed bug 1340728: pt-online-schema-change doesn't work with HASH indexes
* Fixed bug 1253872: pt-table-checksum max load 20% rounds down
* Fixed bug 1340364: some shell tools output error when queried for --version 

v2.2.9 released 2014-07-08
==========================

Percona Toolkit 2.2.9 has been released. This release contains five bug fixes.

Bugs Fixed:

* Fixed bug 1335960: pt-query-digest could not parse the binlogs from MySQL 5.6 because the binlog format was changed.

* Fixed bug 1315130: pt-online-schema-change did not find child tables as expected. It could incorrectly locate tables which reference a table with the same name in a different schema and could miss tables referencing the altered table if they were in a different schema.

* Fixed bug 1335322: pt-stalk would fail when variable or threshold was non-integer.

* Fixed bug 1258135: pt-deadlock-logger was inserting older deadlocks into the ``deadlock`` table even if it was already there creating unnecessary noise. For example, if the deadlock happened 1 year ago, and MySQL keeps it in the memory and pt-deadlock-logger would ``INSERT`` it into ``percona.deadlocks`` table every minute all the time until server was restarted. This was fixed by comparing with the last deadlock fingerprint before issuing the ``INSERT`` query.

* Fixed bug 1329422: pt-online-schema-change foreign-keys-method=none can break FK constraints in a way that is hard to recover from. Allthough this method of handling foreign key constraints is provided so that the database administrator can disable the tool's built-in functionality if desired, a warning and confirmation request when using alter-foreign-keys-method "none" has been added to warn users when using this option.

Changelog
---------

* Fixed bug 1258135: pt-deadlock-logger introduces a noise to MySQL
* Fixed bug 1329422: pt-online-schema-change foreign-keys-method=none breaks constraints 
* Fixed bug 1315130: pt-online-schema-change not properly detecting foreign keys 
* Fixed bug 1335960: pt-query-digest cannot parse binlogs from 5.6
* Fixed bug 1335322: pt-stalk fails when variable or threshold is non-integer 

v2.2.8 released 2014-06-04
==========================

Percona Toolkit 2.2.8 has been released. This release has two new features and six bug fixes.

New Features:

* pt-agent has been replaced by percona-agent. More information on percona-agent can be found in the `Introducing the 3-Minute MySQL Monitor <http://www.mysqlperformanceblog.com/2014/05/23/3-minute-mysql-monitor/>`_ blogpost.
* pt-slave-restart now supports MySQL 5.6 global transaction IDs.

* pt-table-checkum now has new --plugin option which is similar to pt-online-schema-change --plugin

Bugs Fixed:

* Fixed bug 1254233: pt-mysql-summary was showing blank InnoDB section for 5.6 because it was using ``have_innodb`` variable which was removed in MySQL 5.6.

* Fixed bug 965553: pt-query-digest didn't fingerprint true/false literals correctly.

* Fixed bug 1286250: pt-online-schema-change was requesting password twice.

* Fixed bug 1295667: pt-deadlock-logger was logging incorrect timestamp because tool wasn't aware of the time-zones. 

* Fixed bug 1304062: when multiple tables were specified with pt-table-checksum --ignore-tables, only one of them would be ignored.

* Fixed bug : pt-show-grant --ask-pass option was asking for password in ``STDOUT`` instead of ``STDERR`` where it could be seen.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Removed pt-agent
* Added pt-slave-restart GTID support
* Added pt-table-checksum --plugin
* Fixed bug 1304062: --ignore-tables does not work correctly
* Fixed bug 1295667: pt-deadlock-logger logs incorrect ts
* Fixed bug 1254233: pt-mysql-summary blank InnoDB section for 5.6
* Fixed bug 1286250: pt-online-schema-change requests password twice
* Fixed bug  965553: pt-query-digest dosn't fingerprint true/false literals correctly
* Fixed bug  290911: pt-show-grant --ask-pass prints "Enter password" to STDOUT

v2.2.7 released 2014-02-20
==========================

Percona Toolkit 2.2.7 has been released. This release has only one bug fix. 

* Fixed bug 1279502: --version-check behaves like spyware

Although never used, --version-check had the ability to get any local program's version.  This fix removed that ability.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

v2.2.6 released 2013-12-18
==========================

Percona Toolkit 2.2.6 has been released. This release has 16 bug fixes and a few new features.  One bug fix is very important, so 2.2 users are strongly encouraged to upgrade:

* Fixed bug 1223458: pt-table-sync deletes child table rows

Buried in the pt-table-sync docs is this warning:

  Also be careful with tables that have foreign key constraints with C<ON DELETE>
  or C<ON UPDATE> definitions because these might cause unintended changes on the
  child tables.

Until recently, either no one had this problem, or no one reported it, or no one realized that pt-table-sync caused it.  In the worst case, pt-table-sync could delete all rows in child tables, which is quite surprising and bad.  As of 2.2.6, pt-table-sync has option --[no]check-child-tables which is on by default.  In cases were this "bug" can happen, pt-table-sync prints a warning and skips the table.  Read the option's docs to learn more.

Another good bug fix is:

* Fixed bug 1217013: pt-duplicate-key-checker misses exact duplicate unique indexes

After saying "pt-duplicate-key-checker hasn't had a bug in years" at enough conferences, users proved us wrong--thanks!  The tool is better now.

* Fixed bug 1195628: pt-online-schema-change gets stuck looking for its own _new table

This was poor feedback from the tool more than a bug.  There was a point in the tool where it waited forever for slaves to catch up, but it did this silently.  Now the tool reports --progress while it's waiting and it reports which slaves, if any, it found and intends to check.  In short: its feedback delivers a better user experience.

Finally, this bug (more like a feature request/change) might be a backwards-incompatible change:

* Fixed bug 1214685: pt-mysql-summary schema dump prompt can't be disabled

The change is that pt-mysql-summary no longer prompts to dump and summarize schemas.  To do this, you must specify --databases or, a new option, --all-databases.  Several users said this behavior was better, so we made the change even though some might consider it a backwards-incompatible change.

Percona Toolkit packages can be downloaded from http://www.percona.com/downloads/percona-toolkit/ or the Percona Software Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Added pt-query-digest support for Percona Server slow log rate limiting
* Added pt-agent --ping
* Added pt-mysql-summary --all-databases
* Added pt-stalk --sleep-collect
* Added pt-table-sync --[no]check-child-tables
* Fixed bug 1249150: PTDEBUG prints some info to STDOUT
* Fixed bug 1248363: pt-agent requires restart after changing MySQL options
* Fixed bug 1248778: pt-agent --install on PXC is not documented
* Fixed bug 1250973: pt-agent --install doesn't check for previous install
* Fixed bug 1250968: pt-agent --install suggest MySQL user isn't quoted
* Fixed bug 1251004: pt-agent --install error about slave is confusing
* Fixed bug 1251726: pt-agent --uninstall fails if agent is running
* Fixed bug 1248785: pt-agent docs don't list privs required for its MySQL user
* Fixed bug 1215016: pt-deadlock-logger docs use pt-fk-error-logger
* Fixed bug 1201443: pt-duplicate-key-checker error when EXPLAIN key_len=0
* Fixed bug 1217013: pt-duplicate-key-checker misses exact duplicate unique indexes
* Fixed bug 1214685: pt-mysql-summary schema dump prompt can't be disabled
* Fixed bug 1195628: pt-online-schema-change gets stuck looking for its own _new table
* Fixed bug 1249149: pt-query-digest stats prints to STDOUT instead of STDERR
* Fixed bug 1071979: pt-stak error parsing df with NFS
* Fixed bug 1223458: pt-table-sync deletes child table rows

v2.2.5 released 2013-10-16
==========================

Percona Toolkit 2.2.5 has been released. This release has four new features and a number of bugfixes.

Query_time histogram has been added to the pt-query-digest JSON output, not the actual chart but the values necessary to render the chart later, so the values for each bucket.

As of pt-table-checksum 2.2.5, skipped chunks cause a non-zero exit status. An exit status of zero or 32 is equivalent to a zero exit status with skipped chunks in previous versions of the tool.

New --no-drop-triggers option has been implemented for pt-online-schema-change in case users want to rename the tables manually, when the load is low.

New --new-table-name option has been added to pt-online-schema-change which can be used to specify the temporary table name.

* Fixed bug #1199589: pt-archiver would delete the data even with the --dry-run option.

* Fixed bug #821692: pt-query-digest didn't distill LOAD DATA correctly.

* Fixed bug #984053: pt-query-digest didn't distill INSERT/REPLACE without INTO correctly.

* Fixed bug #1206677: pt-agent docs were referencing wrong web address.

* Fixed bug #1210537: pt-table-checksum --recursion-method=cluster would crash if no nodes were found.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/ or the Percona Software
Repositories (http://www.percona.com/software/repositories

Changelog
---------

* Added Query_time histogram bucket counts to pt-query-digest JSON output
* Added pt-online-schema-change --[no]drop-triggers option
* Fixed bug #1199589: pt-archiver deletes data despite --dry-run
* Fixed bug #944051: pt-table-checksum has ambiguous exit status
* Fixed bug #1209436: pt-kill --log-dsn may not work on Perl 5.8
* Fixed bug #1210537: pt-table-checksum --recursion-method=cluster crashes if no nodes are found
* Fixed bug #1215608: pt-online-schema-change new table suffix is hard-coded
* Fixed bug #1229861: pt-table-sync quotes float values, can't sync
* Fixed bug #821692: pt-query-digest doesn't distill LOAD DATA correctly
* Fixed bug #984053: pt-query-digest doesn't distill INSERT/REPLACE without INTO correctly
* Fixed bug #1206728: pt-deadlock-logger 2.2 requires DSN on command line
* Fixed bug #1226721: pt-agent on CentOS 5 fails to send data
* Fixed bug #821690: pt-query-digest doesn't distill IF EXISTS correctly
* Fixed bug #1206677: pt-agent docs reference clodu.percona.com

v2.2.4 released 2013-07-18
==========================

Percona Toolkit 2.2.4 has been released. This release two new features and a number of bugfixes. 

pt-query-digest --output json includes query examples as of v2.2.3. Some people might not want this because it exposes real data. New option, --output json-anon, has been implemented. This option will provide the same data without query examples. It's "anonymous" in the sense that there's no identifying data; nothing more than schema and table structs can be inferred from fingerprints. 

When using drop swap with pt-online-schema-change there is some production impact. This impact can be measured because tool outputs the current timestamp on lines for operations that may take awhile.

* Fixed bug #1163735: pt-table-checksum fails if explicit_defaults_for_timestamp is enabled in 5.6
pt-table-checksum would fail if variable explicit_defaults_for_timestamp was enabled in MySQL 5.6.

* Fixed bug #1182856: Zero values causes "Invalid --set-vars value: var=0"
Trying to assign 0 to any variable by using --set-vars option would cause “Invalid --set-vars value” message. 

* Fixed bug #1188264: pt-online-schema-change error copying rows: Undefined subroutine &pt_online_schema_change::get

* Fixed the typo in the pt-online-schema-change code that could lead to a tool crash when copying the rows.

* Fixed bug #1199591: pt-table-checksum doesn't use non-unique index with highest cardinality
pt-table-checksum was using the first non-unique index instead of the one with the highest cardinality due to a sorting bug.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/ or the Percona Software
Repositories (http://www.percona.com/software/repositories

Changelog
---------

* Added pt-query-digest anonymous JSON output
* Added pt-online-schema-change timestamp output
* Fixed bug #1136559: pt-table-checksum: Deep recursion on subroutine "SchemaIterator::_iterate_dbh"
* Fixed bug #1163735: pt-table-checksum fails if explicit_defaults_for_timestamp is enabled in 5.6
* Fixed bug #1182856: Zero values causes "Invalid --set-vars value: var=0"
* Fixed bug #1188264: pt-online-schema-change error copying rows: Undefined subroutine &pt_online_schema_change::get
* Fixed bug #1195034: pt-deadlock-logger error: Use of uninitialized value $ts in pattern match (m//)
* Fixed bug #1199591: pt-table-checksum doesn't use non-unique index with highest cardinality
* Fixed bug #1168434: pt-upgrade reports differences on NULL
* Fixed bug #1172317: pt-sift does not work if pt-stalk did not collect due to a full disk
* Fixed bug #1176010: pt-query-digest doesn't group db and `db` together
* Fixed bug #1137556: pt-heartbeat docs don't account for --utc
* Fixed bug #1168106: pt-variable-advisor has the wrong default value for innodb_max_dirty_pages_pct in 5.5 and 5.6
* Fixed bug #1168110: pt-variable-advisor shows key_buffer_size in 5.6 as unconfigured (even though it is)
* Fixed bug #1171968: pt-query-digest docs don't mention --type=rawlog
* Fixed bug #1174956: pt-query-digest and pt-fingerprint don't strip some multi-line comments


v2.2.3 released 2013-06-17
==========================

Percona Toolkit 2.2.3 has been released which has only two changes: pt-agent
and a bug fix for pt-online-schema-change.  pt-agent is not a command line
tool but a client-side agent for Percona Cloud Tools.  Visit
https://cloud.percona.com for more information.  The pt-online-schema-change
bug fix is bug 1188002: pt-online-schema-change causes "ERROR 1146 (42S02):
"Table 'db._t_new' doesn't exist".  This happens when the tool's triggers
cannot be dropped.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/ or the Percona Software
Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Added new tool: pt-agent
* Fixed bug 1188002: pt-online-schema-change causes "ERROR 1146 (42S02): Table 'db._t_new' doesn't exist"

v2.2.2 released 2013-04-24
==========================

Percona Toolkit 2.2.2 has been released.  This is the second release of
the 2.2 series and aims to fix bugs in the previous release and provide
usability enhacements to the toolkit.

Users may note the revival of the --show-all option in pt-query-digest.
This had been removed in 2.2.1, but resulted in too much output in
certain cases.

A new --recursion-method was added to pt-table-checksum: cluster.  This
method attempts to auto-discover cluster nodes, alleviating the need to
specify cluster node DSNs in a DSN table (--recursion-method=dsn).

The following highlights some of the more interesting and "hot" bugs in
this release:

* Bug #1127450: pt-archiver --bulk-insert may corrupt data

pt-archiver --bulk-insert didn't work with --charset UTF-8. This revealed
a case where the tool could corrupt data by double-encoding.  This is now
fixed, but remains relatively dangerous if using DBD::mysql 3.0007 which
does not handle UTF-8 properly.

* Bug #1163372: pt-heartbeat --utc --check always returns 0

Unfortunately, the relatively new --utc option for pt-heart was still
broken because "[MySQL] interprets date as a value in the current time zone
and converts it to an internal value in UTC."  Now the tool works correctly
with --utc by specifying "SET time_zone='+0:00'", and older versions of
the tool can be made to work by specifying --set-vars "time_zone='+0:00'".

* Bug #821502: Some tools don't have --help or --version

pt-align, pt-mext, pt-pmp and pt-sift now have both options.

This is another solid bug fix release, and all users are encouraged to upgrade.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/ or the Percona Software
Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Added --show-all to pt-query-digest
* Added --recursion-method=cluster to pt-table-checksum
* Fixed bug 1127450: pt-archiver --bulk-insert may corrupt data
* Fixed bug 1163372: pt-heartbeat --utc --check always returns 0
* Fixed bug 1156901: pt-query-digest --processlist reports duplicate queries for replication thread
* Fixed bug 1160338: pt-query-digest 2.2 prints unwanted debug info on tcpdump parsing errors
* Fixed bug 1160918: pt-query-digest 2.2 prints too many string values
* Fixed bug 1156867: pt-stalk prints the wrong variable name in verbose mode when --function is used
* Fixed bug 1081733: pt-stalk plugins can't access the real --prefix
* Fixed bug 1099845: pt-table-checksum pxc same_node function incorrectly uses wsrep_sst_receive_address
* Fixed bug  821502: Some tools don't have --help or --version
* Fixed bug  947893: Some tools use @@hostname without /*!50038*/
* Fixed bug 1082406: An explicitly set wsrep_node_incoming_address may make SHOW STATUS LIKE 'wsrep_incoming_addresses' return a portless address

v2.2.1 released 2013-03-14
==========================

Percona Toolkit 2.2.1 has been released.  This is the first release in
the new 2.2 series which supersedes the 2.1 series and renders the 2.0
series obsolete.  We plan to do one more bug fix release for 2.1 (2.1.10),
but otherwise all new development and fixes and will now focus on 2.2.

Percona Toolkit 2.2 has been several months in the making, and it turned
out very well, with many more new features, changes, and improvements than
originally anticipated.  Here are the highlights:

----

* Official support for MySQL 5.6

We started beta support for MySQL 5.6 in 2.1.8 when 5.6 was still beta.
Now that 5.6 is GA, so is our support for it.  Check out the Percona Toolkit
supported platforms and versions:
http://www.percona.com/mysql-support/policies/percona-toolkit-supported-platforms-and-versions

When you upgrade to MySQL 5.6, be sure to upgrade to Percona Toolkit 2.2, too.

* Official support for Percona XtraDB Cluster (PXC)

We also started beta support for Percona XtraDB Cluster in 2.1.8, but
now that support is official in 2.2 because we have had many months to
work with PXC and figure out which tools work with it and how.  There's
still one noticeable omission: pt-table-sync.  It's still unclear if
or how one would sync a cluster that, in theory, doesn't become out-of-sync.
As Percona XtraDB Cluster develops, Percona Toolkit will continue to
evolve to support it.

* pt-online-schema-change (pt-osc) is much more resilient

pt-online-schema-change 2.1 has been a great success, and people have been
using it for evermore difficult and challenging tasks.  Consequently, we
needed to make it "try harder", even though it already tried pretty hard
to keep working despite recoverable errors and such.  Whereas pt-osc 2.1
only retries certain operations, pt-osc 2.2 retries every critical operation,
and its tries and wait time between tries for all operations are configurable.
Also, we removed --lock-wait-timeout which set innodb_lock_wait_timeout
because that now conflicts, or is at least confused with, lock_wait_timeout
(introduced in MySQL 5.5) for metadata locks.  Now --set-vars is used to
set both of these (or any) system variables.  For a quick intro to metadata
locks and how they may affect you, see Ovais's article:
http://www.mysqlperformanceblog.com/2013/02/01/implications-of-metadata-locking-changes-in-mysql-5-5/

What does this all mean?  In short: pt-online-schema-change 2.2 is far more
resilient out of the box.  It's also aware of metadata locks now, whereas
2.1 was not really aware of them.  And it's highly configurable, so you can
make the tool try _very_ hard to keep working.

* pt-upgrade is brand-new

pt-upgrade was written once long ago, thrown into the world, and then never
heard from again... until now.  Now that we have four base versions of
MySQL (5.0, 5.1, 5.5, and 5.6), plus at least four major forks (Percona
Server, MariaDB, Percona XtraDB Cluster, and MariaDB Galera Cluster),
upgrades are fashionable, so to speak.  Problem is: "original" pt-upgrade
was too noisy and too complex.  pt-upgrade 2.2 is far simpler and far
easier to use.  It's basically what you expect from such a tool.

Moreover, it has a really helpful new feature: "reference results", i.e.
saved results from running queries on a server.  Granted, this can take
*a lot* of disk space, but it allows you to "run now, compare later."

If you're thinking about upgrading, give pt-upgrade a try.  It also reads
every type of log now (slow, general, binary, and tcpdump), so you shouldn't
have a problem finding queries to run and compare.

* pt-query-digest is simpler

pt-query-digest 2.2 has fewer options now.  Basically, we re-focused it
on its primary objective: analyzing MySQL query logs.  So the ability
to parse memcached, Postgres, Apache, and other logs was removed.  We
also removed several options that probably nobody ever used, and
changed/renamed other options to be more logical.  The result is a simpler,
more focused tool, i.e. less overwhelming.

Also, pt-query-digest 2.2 can save results in JSON format (--output=json).
This feature is still in development while we determine the optimal
JSON structure.

* Version check is on by default

Way back in 2.1.4, released September/October 2012, we introduced a feature
called "version check" into most tools: http://percona.com/version-check
It's like a lot of software that automatically checks for updates, but
it's also more: it's a free service from Percona that advises when certain
programs (Percona Toolkit tools, MySQL, Perl, etc.) are either out of date
or are known bad versions.  For example, there are two versions of the
DBD::mysql Perl module that have problems.  And there are certain versions
of MySQL that have critical bugs.  Version check will warn you about these
if your system is running them.

What's new in 2.2 is that, whereas this feature (specifically, the option
in tools: --version-check) was off by default, now it's on by default.
If the IO::Socket::SSL Perl module is installed (easily available through
your package manager), it will use a secure (https) connection over the web,
else it will use a standard (http) connection.

Check out http://percona.com/version-check for more information.

* pt-query-advisor, pt-tcp-model, pt-trend, and pt-log-player are gone

We removed pt-query-advisor, pt-tcp-model, pt-trend, and pt-log-player.
Granted, no tool is ever really gone: if you need one of these tools,
get it from 2.1.  pt-log-player is now superseded by Percona Playback
(http://www.percona.com/doc/percona-playback/).  pt-query-advisor was
removed so that we can focus our efforts on its online counterpart instead:
https://tools.percona.com/query-advisor.  The other tools were special
projects that were not widely used.

* pt-stalk and pt-mysql-summary have built-in MySQL options

No more "pt-stalk -- -h db1 -u me".  pt-stalk 2.2 and pt-mysql-summary 2.2
have all the standard MySQL options built-in, like other tools: --user,
--host, --port, --password, --socket, --defaults-file.  So now the command
line is what you expect: pt-stalk -h dhb1 -u me.

* pt-stalk --no-stalk is no longer magical

Originally, pt-stalk --no-stalk was meant to simulate pt-collect, i.e.
collect once and exit.  To do that, the tool magically set some options
and clobbered others, resulting in no way to do repeated collections
at intervals.  Now --no-stalk means only that: don't stalk, just collect,
respecting --interval and --iterations as usual.  So to collect once
and exit: pt-stalk --no-stalk --iterations 1.

* pt-fk-error-logger and pt-deadlock-logger are standardized

Similar to the pt-stalk --no-stalk changes, pt-fk-error-logger and
pt-deadlock-logger received mini overhauls in 2.2 to make their
run-related options (--run-time, --interval, --iterations) standard.
If you hadn't noticed, one tool would run forever by default, while
the other would run once and exit.  And each treated their run-related
options a little differently.  This magic is gone now: both tools run
forever by default, so specify --iterations or --run-time to limit how
long they run.

----

There were other miscellaneous bug fixes, too.  See
https://launchpad.net/percona-toolkit/+milestone/2.2.1 for the full list.

As the first release in a new series, 2.2 features are not yet finalized.
In other words, we may change things like the pt-query-digest --output json
format in future releases after receiving real-world feedback.

Percona Toolkit 2.2 is an exciting release with many helpful new
features.  Users are encouraged to begin upgrading, particularly given
that, except for the forthcoming 2.1.10 release, no more work will be
done on 2.1 (unless you're a Percona customer with a support contract or
other agreement).

If you upgrade from 2.1 to 2.2, be sure to re-read tools' documentation
to see what has changed because much as changed for certain tools.

Percona Toolkit packages can be downloaded from
http://www.percona.com/downloads/percona-toolkit/ or the Percona Software
Repositories (http://www.percona.com/software/repositories/).

Changelog
---------

* Official support for MySQL 5.6
* Official support for Percona XtraDB Cluster
* Redesigned pt-query-digest
* Redesigned pt-upgrade
* Redesigned pt-fk-error-logger
* Redesigned pt-deadlock-logger
* Changed --set-vars in all tools
* Renamed --retries to --tries in pt-online-schema-change
* Added --check-read-only to pt-heartbeat
* Added MySQL options to pt-mysql-summary
* Added MySQL options to pt-stalk
* Removed --lock-wait-timeout from pt-online-schema-change (use --set-vars)
* Removed --lock-wait-timeout from pt-table-checksum (use --set-vars)
* Removed pt-query-advisor
* Removed pt-tcp-model
* Removed pt-trend
* Removed pt-log-player
* Enabled --version-check by default in all tools
* Fixed bug 1008796: Several tools don't have --database
* Fixed bug 1087319: Quoter::serialize_list() doesn't handle multiple NULL values
* Fixed bug 1086018: pt-config-diff needs to parse wsrep_provider_options
* Fixed bug 1056838: pt-fk-error-logger --run-time works differently than pt-deadlock-logger --run-time
* Fixed bug 1093016: pt-online-schema-change doesn't retry RENAME TABLE
* Fixed bug 1113301: pt-online-schema-change blocks on metadata locks
* Fixed bug 1125665: pt-stalk --no-stalk silently clobbers other options, acts magically
* Fixed bug 1019648: pt-stalk truncates InnoDB status if there are too many transactions
* Fixed bug 1087804: pt-table-checksum doesn't warn if no slaves are found

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
* Fixed bug 930533: pt-sift looking for ``*-processlist1;`` broken compatibility with pt-stalk
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

Changelog
---------

* Fixed bug 1279502: --version-check behaves like spyware

Changelog
---------

* Fixed bug 1402776: Improved fix (protocol parser fix): error when parsing tcpdump capture with pt-query-digest
* Fixed bug 1632522: pt-osc: Fails with duplicate key in table for self-referencing (Thanks Amiel Marqeta)
* Fixed bug 1654668: pt-summary exists with an error (Thanks Marcelo Altmann)
* New tool         : pt-mongodb-summary 
* New tool         : pt-mongodb-query-digest

Percona Toolkit 3.0.0 RC includes the following changes:

New Features

* Added ``pt-mongodb-summary`` tool

* Added ``pt-mongodb-query-profiler`` tool

Bug fixes

* 1402776: Updated ``MySQLProtocolParser`` to fix error when parsing ``tcpdump`` capture with ``pt-query-digest``

* 1632522: Fixed failure of ``pt-online-schema-change`` when altering a table with a self-referencing foreign key (Thanks Marcelo Altmann)

* 1654668: Fixed failure of ``pt-summary`` on Red Hat and derivatives (Thanks Marcelo Altmann)
