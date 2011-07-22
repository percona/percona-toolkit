
########################
pt-duplicate-key-checker
########################

.. highlight:: perl


****
NAME
****


pt-duplicate-key-checker - Find duplicate indexes and foreign keys on MySQL tables.


********
SYNOPSIS
********


Usage: pt-duplicate-key-checker [OPTION...] [DSN]

pt-duplicate-key-checker examines MySQL tables for duplicate or redundant
indexes and foreign keys.  Connection options are read from MySQL option files.


.. code-block:: perl

    pt-duplicate-key-checker --host host1



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-duplicate-key-checker is a read-only tool that executes SHOW CREATE TABLE and
related queries to inspect table structures, and thus is very low-risk.

At the time of this release, there is an unconfirmed bug that causes the tool
to crash.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-duplicate-key-checker <http://www.percona.com/bugs/pt-duplicate-key-checker>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


This program examines the output of SHOW CREATE TABLE on MySQL tables, and if
it finds indexes that cover the same columns as another index in the same
order, or cover an exact leftmost prefix of another index, it prints out
the suspicious indexes.  By default, indexes must be of the same type, so a
BTREE index is not a duplicate of a FULLTEXT index, even if they have the same
columns.  You can override this.

It also looks for duplicate foreign keys.  A duplicate foreign key covers the
same columns as another in the same table, and references the same parent
table.


*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--all-structs
 
 Compare indexes with different structs (BTREE, HASH, etc).
 
 By default this is disabled, because a BTREE index that covers the same columns
 as a FULLTEXT index is not really a duplicate, for example.
 


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
 NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
 without the utf8 layer, and runs SET NAMES after connecting to MySQL.
 


--[no]clustered
 
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
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--databases
 
 short form: -d; type: hash
 
 Check only this comma-separated list of databases.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute pathname.
 


--engines
 
 short form: -e; type: hash
 
 Check only tables whose storage engine is in this comma-separated list.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--ignore-databases
 
 type: Hash
 
 Ignore this comma-separated list of databases.
 


--ignore-engines
 
 type: Hash
 
 Ignore this comma-separated list of storage engines.
 


--ignore-order
 
 Ignore index order so KEY(a,b) duplicates KEY(b,a).
 


--ignore-tables
 
 type: Hash
 
 Ignore this comma-separated list of tables.  Table names may be qualified with
 the database name.
 


--key-types
 
 type: string; default: fk
 
 Check for duplicate f=foreign keys, k=keys or fk=both.
 


--password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


--pid
 
 type: string
 
 Create the given PID file.  The file contains the process ID of the script.
 The PID file is removed when the script exits.  Before starting, the script
 checks if the PID file already exists.  If it does not, then the script creates
 and writes its own PID to it.  If it does, then the script checks the following:
 if the file contains a PID and a process is running with that PID, then
 the script dies; or, if there is no process running with that PID, then the
 script overwrites the file with its own PID and starts; else, if the file
 contains no PID, then the script dies.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--[no]sql
 
 default: yes
 
 Print DROP KEY statement for each duplicate key.  By default an ALTER TABLE
 DROP KEY statement is printed below each duplicate key so that, if you want to
 remove the duplicate key, you can copy-paste the statement into MySQL.
 
 To disable printing these statements, specify --nosql.
 


--[no]summary
 
 default: yes
 
 Print summary of indexes at end of output.
 


--tables
 
 short form: -t; type: hash
 
 Check only this comma-separated list of tables.
 
 Table names may be qualified with the database name.
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


--verbose
 
 short form: -v
 
 Output all keys and/or foreign keys found, not just redundant ones.
 


--version
 
 Show version and exit.
 



***********
DSN OPTIONS
***********


These DSN options are used to create a DSN.  Each option is given like
\ ``option=value``\ .  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the \ ``=``\  and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the percona-toolkit manpage for full details.


\* A
 
 dsn: charset; copy: yes
 
 Default character set.
 


\* D
 
 dsn: database; copy: yes
 
 Default database.
 


\* F
 
 dsn: mysql_read_default_file; copy: yes
 
 Only read default options from the given file
 


\* h
 
 dsn: host; copy: yes
 
 Connect to host.
 


\* p
 
 dsn: password; copy: yes
 
 Password to use when connecting.
 


\* P
 
 dsn: port; copy: yes
 
 Port number to use for connection.
 


\* S
 
 dsn: mysql_socket; copy: yes
 
 Socket file to use for connection.
 


\* u
 
 dsn: user; copy: yes
 
 User for login if not current user.
 



***********
DOWNLOADING
***********


Visit `http://www.percona.com/software/percona-toolkit/ <http://www.percona.com/software/percona-toolkit/>`_ to download the
latest release of Percona Toolkit.  Or, get the latest release from the
command line:


.. code-block:: perl

    wget percona.com/get/percona-toolkit.tar.gz
 
    wget percona.com/get/percona-toolkit.rpm
 
    wget percona.com/get/percona-toolkit.deb


You can also get individual tools from the latest release:


.. code-block:: perl

    wget percona.com/get/TOOL


Replace \ ``TOOL``\  with the name of any tool.


***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-duplicate-key-checker ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


*******************
SYSTEM REQUIREMENTS
*******************


You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-duplicate-key-checker <http://www.percona.com/bugs/pt-duplicate-key-checker>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.
Include the following information in your bug report:


\* Complete command-line used to run the tool



\* Tool "--version"



\* MySQL version of all servers involved



\* Output from the tool including STDERR



\* Input files (log/dump/config files, etc.)



If possible, include debugging output by running the tool with \ ``PTDEBUG``\ ;
see "ENVIRONMENT".


*******
AUTHORS
*******


Baron Schwartz and Daniel Nichter


*********************
ABOUT PERCONA TOOLKIT
*********************


This tool is part of Percona Toolkit, a collection of advanced command-line
tools developed by Percona for MySQL support and consulting.  Percona Toolkit
was forked from two projects in June, 2011: Maatkit and Aspersa.  Those
projects were created by Baron Schwartz and developed primarily by him and
Daniel Nichter, both of whom are employed by Percona.  Visit
`http://www.percona.com/software/ <http://www.percona.com/software/>`_ for more software developed by Percona.


********************************
COPYRIGHT, LICENSE, AND WARRANTY
********************************


This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue \`man perlgpl' or \`man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.


*******
VERSION
*******


Percona Toolkit v1.0.0 released 2011-08-01

