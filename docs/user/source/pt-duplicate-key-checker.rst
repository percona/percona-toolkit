.. program:: pt-duplicate-key-checker

=====================================
 :program:`pt-duplicate-key-checker`
=====================================

.. highlight:: perl

NAME
====

:program:`pt-duplicate-key-checker` - Find duplicate indexes and foreign keys on MySQL tables.

SYNOPSIS
========

Usage
-----

::

   pt-duplicate-key-checker [OPTION...] [DSN]

:program:`pt-duplicate-key-checker` examines |MySQL| tables for duplicate or redundant indexes and foreign keys. Connection options are read from MySQL option files.

.. code-block:: perl

    pt-duplicate-key-checker --host host1

RISKS
=====

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-duplicate-key-checker` is a read-only tool that executes ``SHOW CREATE TABLE`` and related queries to inspect table structures, and thus is very low-risk.

At the time of this release, there is an unconfirmed bug that causes the tool
to crash.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-duplicate-key-checker <http://www.percona.com/bugs/pt-duplicate-key-checker>`_.

See also "BUGS" for more information on filing bugs and getting help.

DESCRIPTION
===========

This program examines the output of ``SHOW CREATE TABLE`` on |MySQL| tables, and if it finds indexes that cover the same columns as another index in the same
order, or cover an exact leftmost prefix of another index, it prints out
the suspicious indexes.  By default, indexes must be of the same type, so a
BTREE index is not a duplicate of a FULLTEXT index, even if they have the same
columns.  You can override this.

It also looks for duplicate foreign keys. A duplicate foreign key covers the
same columns as another in the same table, and references the same parent
table.

OPTIONS
=======

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.

.. option:: --all-structs
 
 Compare indexes with different structs (BTREE, HASH, etc).
 
 By default this is disabled, because a BTREE index that covers the same columns
 as a FULLTEXT index is not really a duplicate, for example.
 
.. option:: --ask-pass
 
 Prompt for a password when connecting to MySQL.
 
.. option:: --charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
 NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
 without the utf8 layer, and runs SET NAMES after connecting to MySQL.
 
.. option:: --[no]clustered
 
 default: yes
 
 PK columns appended to secondary key is duplicate.
 
 Detects when a suffix of a secondary key is a leftmost prefix of the primary
 key, and treats it as a duplicate key.  Only detects this condition on storage
 engines whose primary keys are clustered (currently InnoDB and solidDB).
 
 Clustered storage engines append the primary key columns to the leaf nodes of
 all secondary keys anyway, so you might consider it redundant to have them
 appear in the internal nodes as well.  Of course, you may also want them in the
 internal nodes, because just having them at the leaf nodes won't help for some
 queries.  It does help for covering index queries, however.
 
 Here's an example of a key that is considered redundant with this option:
 
 
 .. code-block:: perl
 
    PRIMARY KEY  (`a`)
    KEY `b` (`b`,`a`)
 
 
 The use of such indexes is rather subtle.  For example, suppose you have the
 following query:
 
 .. code-block:: perl
 
    SELECT ... WHERE b=1 ORDER BY a;
 
 This query will do a filesort if we remove the index on \ ``b,a``\ .  But if we
 shorten the index on \ ``b,a``\  to just \ ``b``\  and also remove the ORDER BY, the query
 should return the same results.
 
 The tool suggests shortening duplicate clustered keys by dropping the key
 and re-adding it without the primary key prefix.  The shortened clustered
 key may still duplicate another key, but the tool cannot currently detect
 when this happens without being ran a second time to re-check the newly
 shortened clustered keys.  Therefore, if you shorten any duplicate clustered
 keys, you should run the tool again.
 
.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 
.. option:: --databases
 
 short form: -d; type: hash
 
 Check only this comma-separated list of databases.
 
.. option:: --defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute pathname.
 
.. option:: --engines
 
 short form: -e; type: hash
 
 Check only tables whose storage engine is in this comma-separated list.
 
.. option:: --help
 
 Show help and exit.
 
.. option:: --host
 
 short form: -h; type: string
 
 Connect to host.
 
.. option:: --ignore-databases
 
 type: Hash
 
 Ignore this comma-separated list of databases.
 
.. option:: --ignore-engines
 
 type: Hash
 
 Ignore this comma-separated list of storage engines.
 
.. option:: --ignore-order
 
 Ignore index order so KEY(a,b) duplicates KEY(b,a).
 
.. option:: --ignore-tables
 
 type: Hash
 
 Ignore this comma-separated list of tables.  Table names may be qualified with
 the database name.
 
.. option:: --key-types
 
 type: string; default: fk
 
 Check for duplicate f=foreign keys, k=keys or fk=both.
 
.. option:: --password
 
 short form: -p; type: string
 
 Password to use when connecting.
 
.. option:: --pid
 
 type: string
 
 Create the given PID file.  The file contains the process ID of the script.
 The PID file is removed when the script exits.  Before starting, the script
 checks if the PID file already exists.  If it does not, then the script creates
 and writes its own PID to it.  If it does, then the script checks the following:
 if the file contains a PID and a process is running with that PID, then
 the script dies; or, if there is no process running with that PID, then the
 script overwrites the file with its own PID and starts; else, if the file
 contains no PID, then the script dies.
 
.. option:: --port
 
 short form: -P; type: int
 
 Port number to use for connection.
 
.. option:: --set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 
.. option:: --socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 
.. option:: --[no]sql
 
 default: yes
 
 Print DROP KEY statement for each duplicate key.  By default an ALTER TABLE
 DROP KEY statement is printed below each duplicate key so that, if you want to
 remove the duplicate key, you can copy-paste the statement into MySQL.
 
 To disable printing these statements, specify --nosql.
 
.. option:: --[no]summary
 
 default: yes
 
 Print summary of indexes at end of output.
 
.. option:: --tables
 
 short form: -t; type: hash
 
 Check only this comma-separated list of tables.
 
 Table names may be qualified with the database name.
 
.. option:: --user
 
 short form: -u; type: string
 
 User for login if not current user.
 
.. option:: --verbose
 
 short form: -v
 
 Output all keys and/or foreign keys found, not just redundant ones.
 
.. option:: --version
 
 Show version and exit.
 
DSN OPTIONS
===========


These DSN options are used to create a DSN.  Each option is given like
\ ``option=value``\ .  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the \ ``=``\  and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the percona-toolkit manpage for full details.


\* A
 
 dsn: charset; copy: yes
 
 Default character set.
 
  * ``D``
 
 dsn: database; copy: yes
 
 Default database.
 


  * ``F``
 
 dsn: mysql_read_default_file; copy: yes
 
 Only read default options from the given file
 


  * ``h``
 
 dsn: host; copy: yes
 
 Connect to host.
 
  * ``p``
 
 dsn: password; copy: yes
 
 Password to use when connecting.
 
  * ``P``

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

    PTDEBUG=1 pt-duplicate-key-checker ... > FILE 2>&1

Be careful: debugging output is voluminous and can generate several megabytes
of output.

SYSTEM REQUIREMENTS
===================

You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.

BUGS
====

For a list of known bugs, see `http://www.percona.com/bugs/pt-duplicate-key-checker <http://www.percona.com/bugs/pt-duplicate-key-checker>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======

Baron Schwartz and Daniel Nichter


COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

:doc:`pt-duplicate-key-checker` 1.0.1

