.. program:: pt-index-usage

===========================
 :program:`pt-index-usage`
===========================

.. highlight:: perl


NAME
====

 :program:`pt-index-usage` - Read queries from a log and analyze how they use indexes.


SYNOPSIS
========


Usage
-----

::

   pt-index-usage [OPTION...] [FILE...]

 :program:`pt-index-usage` reads queries from logs and analyzes how they use indexes.

Analyze queries in slow.log and print reports:


.. code-block:: perl

   pt-index-usage /path/to/slow.log --host localhost


Disable reports and save results to mk database for later analysis:


.. code-block:: perl

   pt-index-usage slow.log --no-report --save-results-database mk



RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

This tool is read-only unless you use :option:`--save-results-database`.  It reads a
log of queries and EXPLAIN them.  It also gathers information about all tables
in all databases.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-index-usage <http://www.percona.com/bugs/pt-index-usage>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========


This tool connects to a |MySQL| database server, reads through a query log, and
uses EXPLAIN to ask |MySQL| how it will use each query.  When it is finished, it
prints out a report on indexes that the queries didn't use.

The query log needs to be in |MySQL|'s slow query log format.  If you need to
input a different format, you can use pt-query-digest to translate the
formats.  If you don't specify a filename, the tool reads from ``STDIN``.

The tool runs two stages.  In the first stage, the tool takes inventory of all
the tables and indexes in your database, so it can compare the existing indexes
to those that were actually used by the queries in the log.  In the second
stage, it runs EXPLAIN on each query in the query log.  It uses separate
database connections to inventory the tables and run EXPLAIN, so it opens two
connections to the database.

If a query is not a SELECT, it tries to transform it to a roughly equivalent
SELECT query so it can be EXPLAINed.  This is not a perfect process, but it is
good enough to be useful.

The tool skips the EXPLAIN step for queries that are exact duplicates of those
seen before.  It assumes that the same query will generate the same EXPLAIN plan
as it did previously (usually a safe assumption, and generally good for
performance), and simply increments the count of times that the indexes were
used.  However, queries that have the same fingerprint but different checksums
will be re-EXPLAINed.  Queries that have different literal constants can have
different execution plans, and this is important to measure.

After EXPLAIN-ing the query, it is necessary to try to map aliases in the query
back to the original table names.  For example, consider the EXPLAIN plan for
the following query:


.. code-block:: perl

   SELECT * FROM tbl1 AS foo;


The EXPLAIN output will show access to table \ ``foo``\ , and that must be translated
back to \ ``tbl1``\ .  This process involves complex parsing.  It is generally very
accurate, but there is some chance that it might not work right.  If you find
cases where it fails, submit a bug report and a reproducible test case.

Queries that cannot be EXPLAINed will cause all subsequent queries with the
same fingerprint to be blacklisted.  This is to reduce the work they cause, and
prevent them from continuing to print error messages.  However, at least in
this stage of the tool's development, it is my opinion that it's not a good
idea to preemptively silence these, or prevent them from being EXPLAINed at
all.  I am looking for lots of feedback on how to improve things like the
query parsing.  So please submit your test cases based on the errors the tool
prints!


OUTPUT
======

After it reads all the events in the log, the tool prints out DROP statements
for every index that was not used.  It skips indexes for tables that were never
accessed by any queries in the log, to avoid false-positive results.

If you don't specify :option:`--quiet`, the tool also outputs warnings about
statements that cannot be EXPLAINed and similar.  These go to standard error.

Progress reports are enabled by default (see :option:`--progress`).  These also go to
standard error.


OPTIONS
=======

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


.. option:: --ask-pass
 
 Prompt for a password when connecting to |MySQL|.
 

.. option:: --charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets *Perl* 's binmode on
 ``STDOUT`` to utf8, passes the mysql_enable_utf8 option to ``DBD::mysql``, and
 runs SET NAMES UTF8 after connecting to |MySQL|.  Any other value sets
 binmode on ``STDOUT`` without the utf8 layer, and runs SET NAMES after
 connecting to |MySQL|.
 

.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 

.. option:: --create-save-results-database
 
 Create the :option:`--save-results-database` if it does not exist.
 
 If the :option:`--save-results-database` already exists and this option is
 specified, the database is used and the necessary tables are created if
 they do not already exist.
 

.. option:: --[no]create-views
 
 Create views for :option:`--save-results-database` example queries.
 
 Several example queries are given for querying the tables in the
 :option:`--save-results-database`.  These example queries are, by default, created
 as views.  Specifying \ ``--no-create-views``\  prevents these views from being
 created.
 

.. option:: --database
 
 short form: -D; type: string
 
 The database to use for the connection.
 

.. option:: --databases
 
 short form: -d; type: hash
 
 Only get tables and indexes from this comma-separated list of databases.
 

.. option:: --databases-regex
 
 type: string
 
 Only get tables and indexes from database whose names match this *Perl*  regex.
 

.. option:: --defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute pathname.
 

.. option:: --drop
 
 type: Hash; default: non-unique
 
 Suggest dropping only these types of unused indexes.
 
 By default :program:`pt-index-usage` will only suggest to drop unused secondary indexes, not primary or unique indexes.  You can specify which types of unused indexes
 the tool suggests to drop: primary, unique, non-unique, all.
 
 A separate \ ``ALTER TABLE``\  statement for each type is printed.  So if you
 specify \ ``--drop all``\  and there is a primary key and a non-unique index,
 the \ ``ALTER TABLE ... DROP``\  for each will be printed on separate lines.
 

.. option:: --empty-save-results-tables
 
 Drop and re-create all pre-existing tables in the :option:`--save-results-database`.
 This allows information from previous runs to be removed before the current run.
 

.. option:: --help
 
 Show help and exit.
 

.. option:: --host
 
 short form: -h; type: string
 
 Connect to host.
 

.. option:: --ignore-databases
 
 type: Hash
 
 Ignore this comma-separated list of databases.
 

.. option:: --ignore-databases-regex
 
 type: string
 
 Ignore databases whose names match this *Perl*  regex.
 

.. option:: --ignore-tables
 
 type: Hash
 
 Ignore this comma-separated list of table names.
 
 Table names may be qualified with the database name.
 

.. option:: --ignore-tables-regex
 
 type: string
 
 Ignore tables whose names match the *Perl*  regex.
 


.. option:: --password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


.. option:: --port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


.. option:: --progress
 
 type: array; default: time,30
 
 Print progress reports to ``STDERR``.  The value is a comma-separated list with two
 parts.  The first part can be percentage, time, or iterations; the second part
 specifies how often an update should be printed, in percentage, seconds, or
 number of iterations.
 

.. option:: --quiet
 
 short form: -q
 
 Do not print any warnings.  Also disables :option:`--progress`.
 

.. option:: --[no]report
 
 default: yes
 
 Print the reports for :option:`--report-format`.
 
 You may want to disable the reports by specifying \ ``--no-report``\  if, for
 example, you also specify :option:`--save-results-database` and you only want
 to query the results tables later.
 

.. option:: --report-format
 
 type: Array; default: drop_unused_indexes
 
 Right now there is only one report: drop_unused_indexes.  This report prints
 SQL statements for dropping any unused indexes.  See also :option:`--drop`.
 
 See also :option:`--[no]report`.
 

.. option:: --save-results-database
 
 type: DSN
 
 Save results to tables in this database.  Information about indexes, queries,
 tables and their usage is stored in several tables in the specified database.
 The tables are auto-created if they do not exist.  If the database doesn't
 exist, it can be auto-created with :option:`--create-save-results-database`.  In this
 case the connection is initially created with no default database, then after
 the database is created, it is USE'ed.
 
 :program:`pt-index-usage` executes INSERT statements to save the results.  Therefore, you  should be careful if you use this feature on a production server.  It might
 increase load, or cause trouble if you don't want the server to be written to,
 or so on.
 
 This is a new feature.  It may change in future releases.
 
 After a run, you can query the usage tables to answer various questions about
 index usage.  The tables have the following CREATE TABLE definitions:
 
 MAGIC_create_indexes:
 
 
 .. code-block:: perl
 
    CREATE TABLE IF NOT EXISTS indexes (
      db           VARCHAR(64) NOT NULL,
      tbl          VARCHAR(64) NOT NULL,
      idx          VARCHAR(64) NOT NULL,
      cnt          BIGINT UNSIGNED NOT NULL DEFAULT 0,
      PRIMARY KEY  (db, tbl, idx)
    )
 
 
 MAGIC_create_queries:
 
 
 .. code-block:: perl
 
    CREATE TABLE IF NOT EXISTS queries (
      query_id     BIGINT UNSIGNED NOT NULL,
      fingerprint  TEXT NOT NULL,
      sample       TEXT NOT NULL,
      PRIMARY KEY  (query_id)
    )
 
 
 MAGIC_create_tables:
 
 
 .. code-block:: perl
 
    CREATE TABLE IF NOT EXISTS tables (
      db           VARCHAR(64) NOT NULL,
      tbl          VARCHAR(64) NOT NULL,
      cnt          BIGINT UNSIGNED NOT NULL DEFAULT 0,
      PRIMARY KEY  (db, tbl)
    )
 
 
 MAGIC_create_index_usage:
 
 
 .. code-block:: perl
 
    CREATE TABLE IF NOT EXISTS index_usage (
      query_id      BIGINT UNSIGNED NOT NULL,
      db            VARCHAR(64) NOT NULL,
      tbl           VARCHAR(64) NOT NULL,
      idx           VARCHAR(64) NOT NULL,
      cnt           BIGINT UNSIGNED NOT NULL DEFAULT 1,
      UNIQUE INDEX  (query_id, db, tbl, idx)
    )
 
 
 MAGIC_create_index_alternatives:
 
 
 .. code-block:: perl
 
    CREATE TABLE IF NOT EXISTS index_alternatives (
      query_id      BIGINT UNSIGNED NOT NULL, -- This query used
      db            VARCHAR(64) NOT NULL,     -- this index, but...
      tbl           VARCHAR(64) NOT NULL,     --
      idx           VARCHAR(64) NOT NULL,     --
      alt_idx       VARCHAR(64) NOT NULL,     -- was an alternative
      cnt           BIGINT UNSIGNED NOT NULL DEFAULT 1,
      UNIQUE INDEX  (query_id, db, tbl, idx, alt_idx),
      INDEX         (db, tbl, idx),
      INDEX         (db, tbl, alt_idx)
    )
 
 
 The following are some queries you can run against these tables to answer common
 questions you might have.  Each query is also created as a view (with |MySQL|
 v5.0 and newer) if :option:`--[no]create-views` is true (it is by default).
 The view names are the strings after the \ ``MAGIC_view_``\  prefix.
 
 Question: which queries sometimes use different indexes, and what fraction of
 the time is each index chosen?  MAGIC_view_query_uses_several_indexes:
 
 .. code-block:: perl
 
   SELECT iu.query_id, CONCAT_WS('.', iu.db, iu.tbl, iu.idx) AS idx,
      variations, iu.cnt, iu.cnt / total_cnt * 100 AS pct
   FROM index_usage AS iu
      INNER JOIN (
         SELECT query_id, db, tbl, SUM(cnt) AS total_cnt,
           COUNT(*) AS variations
         FROM index_usage
         GROUP BY query_id, db, tbl
         HAVING COUNT(*) > 1
      ) AS qv USING(query_id, db, tbl);
 
 
 Question: which indexes have lots of alternatives, i.e. are chosen instead of
 other indexes, and for what queries?  MAGIC_view_index_has_alternates:
 
 .. code-block:: perl
 
   SELECT CONCAT_WS('.', db, tbl, idx) AS idx_chosen,
      GROUP_CONCAT(DISTINCT alt_idx) AS alternatives,
      GROUP_CONCAT(DISTINCT query_id) AS queries, SUM(cnt) AS cnt
   FROM index_alternatives
   GROUP BY db, tbl, idx
   HAVING COUNT(*) > 1;
 
 
 Question: which indexes are considered as alternates for other indexes, and for
 what queries?  MAGIC_view_index_alternates:
 
 .. code-block:: perl
 
   SELECT CONCAT_WS('.', db, tbl, alt_idx) AS idx_considered,
      GROUP_CONCAT(DISTINCT idx) AS alternative_to,
      GROUP_CONCAT(DISTINCT query_id) AS queries, SUM(cnt) AS cnt
   FROM index_alternatives
   GROUP BY db, tbl, alt_idx
   HAVING COUNT(*) > 1;
 
 
 Question: which of those are never chosen by any queries, and are therefore
 superfluous?  MAGIC_view_unused_index_alternates:
 
 .. code-block:: perl
 
   SELECT CONCAT_WS('.', i.db, i.tbl, i.idx) AS idx,
      alt.alternative_to, alt.queries, alt.cnt
   FROM indexes AS i
      INNER JOIN (
         SELECT db, tbl, alt_idx, GROUP_CONCAT(DISTINCT idx) AS alternative_to,
            GROUP_CONCAT(DISTINCT query_id) AS queries, SUM(cnt) AS cnt
         FROM index_alternatives
         GROUP BY db, tbl, alt_idx
         HAVING COUNT(*) > 1
      ) AS alt ON i.db = alt.db AND i.tbl = alt.tbl
        AND i.idx = alt.alt_idx
   WHERE i.cnt = 0;
 
 Question: given a table, which indexes were used, by how many queries, with how
 many distinct fingerprints?  Were there alternatives?  Which indexes were not
 used?  You can edit the following query's SELECT list to also see the query IDs
 in question.  MAGIC_view_index_usage:
 
 .. code-block:: perl
 
   SELECT i.idx, iu.usage_cnt, iu.usage_total,
      ia.alt_cnt, ia.alt_total
   FROM indexes AS i
      LEFT OUTER JOIN (
         SELECT db, tbl, idx, COUNT(*) AS usage_cnt,
            SUM(cnt) AS usage_total, GROUP_CONCAT(query_id) AS used_by
         FROM index_usage
         GROUP BY db, tbl, idx
      ) AS iu ON i.db=iu.db AND i.tbl=iu.tbl AND i.idx = iu.idx
      LEFT OUTER JOIN (
         SELECT db, tbl, idx, COUNT(*) AS alt_cnt,
            SUM(cnt) AS alt_total,
            GROUP_CONCAT(query_id) AS alt_queries
         FROM index_alternatives
         GROUP BY db, tbl, idx
      ) AS ia ON i.db=ia.db AND i.tbl=ia.tbl AND i.idx = ia.idx;
 
 
 Question: which indexes on a given table are vital for at least one query (there
 is no alternative)?  MAGIC_view_required_indexes:
 
 
 .. code-block:: perl
 
     SELECT i.db, i.tbl, i.idx, no_alt.queries
     FROM indexes AS i
        INNER JOIN (
           SELECT iu.db, iu.tbl, iu.idx,
              GROUP_CONCAT(iu.query_id) AS queries
           FROM index_usage AS iu
              LEFT OUTER JOIN index_alternatives AS ia
                 USING(db, tbl, idx)
           WHERE ia.db IS NULL
           GROUP BY iu.db, iu.tbl, iu.idx
        ) AS no_alt ON no_alt.db = i.db AND no_alt.tbl = i.tbl
           AND no_alt.idx = i.idx
     ORDER BY i.db, i.tbl, i.idx, no_alt.queries;


.. option:: --set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these |MySQL| variables.  Immediately after connecting to |MySQL|, this
 string will be appended to SET and executed.


.. option:: --socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 

.. option:: --tables
 
 short form: -t; type: hash
 
 Only get indexes from this comma-separated list of tables.
 

.. option:: --tables-regex
 
 type: string
 
 Only get indexes from tables whose names match this *Perl*  regex.
 

.. option:: --user
 
 short form: -u; type: string
 
 User for login if not current user.
 

.. option:: --version
 
 Show version and exit.
 

DSN OPTIONS
===========

These DSN options are used to create a DSN.  Each option is given like
\ ``option=value``\ .  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the \ ``=``\  and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the percona-toolkit manpage for full details.


  * ``A``
 
 dsn: charset; copy: yes
 
 Default character set.
 

  * ``D``
 
 dsn: database; copy: yes
 
 Database to connect to.
 

  * ``F``
 
 dsn: mysql_read_default_file; copy: yes
 
 Only read default options from the given file
 


  * ``h``
 
 dsn: host; copy: yes
 
 Connect to host.
 

  * ``p``
 
 dsn: password; copy: yes
 
 Password to use when connecting.
 

  * ``p``
 
 dsn: port; copy: yes
 
 Port number to use for connection.
 

  * ``S``
 
 dsn: mysql_socket; copy: yes
 
 Socket file to use for connection.
 

  * ``u``
 
 dsn: user; copy: yes
 
 User for login if not current user.
 

ENVIRONMENT
===========


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to ``STDERR``.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-index-usage ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-index-usage <http://www.percona.com/bugs/pt-index-usage>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======

*Baron Schwartz* and *Daniel Nichter*

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

 :program:`pt-index-usage` 1.0.1

