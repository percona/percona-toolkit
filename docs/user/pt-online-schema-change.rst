
#######################
pt-online-schema-change
#######################

.. highlight:: perl


****
NAME
****


pt-online-schema-change - Perform online, non-blocking table schema changes.


********
SYNOPSIS
********


Usage: pt-online-schema-change [OPTION...] DSN

pt-online-schema-change performs online, non-blocking schema changes to a table.
The table to change must be specified in the DSN \ ``t``\  part, like \ ``t=my_table``\ .
The table can be database-qualified, or the database can be specified with the
"--database" option.

Change the table's engine to InnoDB:


.. code-block:: perl

   pt-online-schema-change   \
     h=127.1,t=db.tbl        \
     --alter "ENGINE=InnoDB" \
     --drop-tmp-table


Rebuild but do not alter the table, and keep the temporary table:


.. code-block:: perl

   pt-online-schema-change h=127.1,t=tbl --database db


Add column to parent table, update child table foreign key constraints:


.. code-block:: perl

   pt-online-schema-change          \
     h=127.1,D=db,t=parent          \
     --alter "ADD COLUMN (foo INT)" \
     --child-tables child1,child2   \
     --update-foreign-keys-method drop_tmp_table



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-online-schema-change reads, writes, alters and drops tables.  Although
it is tested, do not use it in production until you have thoroughly tested it
in your environment!

This tool has not been tested with replication; it may break replication.
See "REPLICATION".

At the time of this release there are no known bugs that pose a serious risk.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-online-schema-change <http://www.percona.com/bugs/pt-online-schema-change>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-online-schema-change performs online, non-blocking schema changes to tables.
Only one table can be altered at a time because triggers are used to capture
and synchronize changes between the table and the temporary table that
will take its place once it has been altered.  Since triggers are used, this
tool only works with MySQL 5.0.2 and newer.

The table to alter is specified by the DSN \ ``t``\  part on the command line,
as shown in the "SYNOPSIS" examples.  A database must also be specified
either by the DSN \ ``D``\  part or by the "--database" option.

If you're using replication, read "REPLICATION" or else you may break
replication.  Performing an online schema change in a replication environment
requires extra planning and care.

In brief, this tool works by creating a temporary table which is a copy of
the original table (the one being altered).  (The temporary table is not
created like \ ``CREATE TEMPORARY TABLE``\ ; we call it temporary because it
ultimately replaces the original table.)  The temporary table is altered,
then triggers are defined on the original table to capture changes made on
it and apply them to the temporary table.  This keeps the two tables in
sync.  Then all rows are copied from the original table to the temporary
table; this part can take awhile.  When done copying rows, the two tables
are swapped by using \ ``RENAME TABLE``\ .  At this point there are two copies
of the table: the old table which used to be the original table, and the
new table which used to be the temporary table but now has the same name
as the original table.  If "--drop-old-table" is specified, then the
old table is dropped.

For example, if you alter table \ ``foo``\ , the tool will create table
\ ``__tmp_foo``\ , alter it, define triggers on \ ``foo``\ , and then copy rows
from \ ``foo``\  to \ ``__tmp_foo``\ .  Once all rows are copied, \ ``foo``\  is renamed
to \ ``__old_foo``\  and \ ``__tmp_foo``\  is renamed to \ ``foo``\ .
If "--drop-old-table" is specified, then \ ``__old_foo``\  is dropped.

The tool preforms the following steps:


.. code-block:: perl

   1. Sanity checks
   2. Chunking
   3. Online schema change


The first two steps cannot be skipped.  The sanity checks help ensure that
running the tool will work and not encounter problems half way through the
whole process.  Chunk is required during the third step when rows from the
old table are copied to the new table.  Currently, only table with a
single-column unique index can be chunked.  If there is any problem in these
two steps, the tool will die.

Most of the tool's work is done in the third step which has 6 phases:


.. code-block:: perl

   1. Create and alter temporary table
   2. Capture changes from the table to the temporary table
   3. Copy rows from the table to the temporary table
   4. Synchronize the table and the temporary table
   5. Swap/rename the table and the temporary table
   6. Cleanup


There are several ways to accomplish an online schema change which differ
in how changes are captured and synced (phases 2 and 4), how rows are copied
(phase 3), and how the tables are swapped (phase 5).  Currently, this tool
employs synchronous triggers (Shlomi's method), \ ``INSERT-SELECT``\ , and
\ ``RENAME TABLE``\  respectively for these phases.

Here are options related to each phase:


.. code-block:: perl

   1. --[no]create-tmp-table, --alter, --tmp-table
   2. (none)
   3. --chunk-size, --sleep
   4. (none)
   5. --[no]rename-tables
   6. --drop-old-table


Options "--check-tables-and-exit" and "--print" are helpful to see what
the tool might do before actually doing it.


***********
REPLICATION
***********


In brief: update slaves first if columns are added or removed.  Certain
ALTER changes like ENGINE may not affect replication.


******
OUTPUT
******


Output to STDOUT is very verbose and should tell you everything that the
tool is doing.  Warnings, errors, and "--progress" are printed to STDERR.


*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--alter
 
 type: string
 
 Semicolon-separated list of \ ``ALTER TABLE``\  statements to apply to the new table.
 The statements should not contain \ ``ALTER TABLE``\ , just what would follow that
 clause.  For example, if you want to \ ``ALTER TABLE ENGINE=InnoDB``\ , the value
 would be \ ``ENGINE=InnoDB``\ .
 
 The value can also be a filename which contains statements, one per line
 with no blank lines and no trailing semicolons.  Each statement will be
 applied in the order it appears in the file.
 


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--bin-log
 
 Allow binary logging (\ ``SET SQL_LOG_BIN=1``\ ).  By default binary logging is
 turned off because in most cases the "--tmp-table" does not need to
 be replicated.  Also, performing an online schema change in a replication
 environment requires careful planning else replication may be broken;
 see "REPLICATION".
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
 NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
 without the utf8 layer, and runs SET NAMES after connecting to MySQL.
 


--check-tables-and-exit
 
 Check that the table can be altered then exit; do not alter the table.
 If you just want to see that the tool can/will work for the given table,
 specify this option.  Even if all checks pass, the tool may still encounter
 problems if, for example, one of the "--alter" statements uses
 incorrect syntax.
 


--child-tables
 
 type: string
 
 Foreign key constraints in these (child) tables reference the table.
 If the table being altered is a parent to tables which reference it with
 foreign key constraints, you must specify those child tables with this option
 so that the tool will update the foreign key constraints after renaming
 tables.  The list of child tables is comma-separated, not quoted, and not
 database-qualified (the database is assumed to be the same as the table)
 If you specify a table that doesn't exist, it is ignored.
 
 Or you can specify just \ ``auto_detect``\  and the tool will query the
 \ ``INFORMATION_SCHEMA``\  to auto-detect any foreign key constraints on the table.
 
 When specifying this option, you must also specify
 "--update-foreign-keys-method".
 


--chunk-size
 
 type: string; default: 1000
 
 Number of rows or data size per chunk.  Data sizes are specified with a
 suffix of k=kibibytes, M=mebibytes, G=gibibytes.  Data sizes are converted
 to a number of rows by dividing by the average row length.
 


--cleanup-and-exit
 
 Cleanup and exit; do not alter the table.  If a previous run fails, you
 may need to use this option to remove any temporary tables, triggers,
 outfiles, etc. that where left behind before another run will succeed.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--[no]create-tmp-table
 
 default: yes
 
 Create the "--tmp-table" with \ ``CREATE TABLE LIKE``\ .  The temporary table
 to which the "--alter" statements are applied is automatically created
 by default with the name \ ``__tmp_TABLE``\  where \ ``TABLE``\  is the original table
 specified by the DSN on the command line.  If you want to create the temporary
 table manually before running this tool, then you must specify
 \ ``--no-create-tmp-table``\  \ **and**\  "--tmp-table" so the tool will use your
 temporary table.
 


--database
 
 short form: -D; type: string
 
 Database of the table.  You can also specify the database with the \ ``D``\  part
 of the DSN given on the command line.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--drop-old-table
 
 Drop the original table after it's swapped with the "--tmp-table".
 After the original table is renamed/swapped with the "--tmp-table"
 it becomes the "old table".  By default, the old table is not dropped
 because if there are problems with the "new table" (the temporary table
 swapped for the original table), then the old table can be restored.
 
 If altering a table with foreign key constraints, you may need to specify
 this option depending on which "--update-foreign-keys-method" you choose.
 


--[no]foreign-key-checks
 
 default: yes
 
 Enforce foreign key checks (FOREIGN_KEY_CHECKS=1).
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


--pid
 
 type: string
 
 Create the given PID file.  The file contains the process ID of the tool's
 instance.  The PID file is removed when the tool exits.  The tool checks for
 the existence of the PID file when starting; if it exists and the process with
 the matching PID exists, the tool exits.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--print
 
 Print SQL statements to STDOUT instead of executing them.  Specifying this
 option allows you to see most of the statements that the tool would execute.
 


--progress
 
 type: array; default: time,30
 
 Print progress reports to STDERR while copying rows.
 
 The value is a comma-separated list with two parts.  The first part can be
 percentage, time, or iterations; the second part specifies how often an update
 should be printed, in percentage, seconds, or number of iterations.
 


--quiet
 
 short form: -q
 
 Do not print messages to STDOUT.  Errors and warnings are still printed to
 STDERR.
 


--[no]rename-tables
 
 default: yes
 
 Rename/swap the original table and the "--tmp-table".  This option
 essentially completes the online schema change process by making the
 temporary table with the new schema take the place of the original table.
 The original tables becomes the "old table" and is dropped if
 "--drop-old-table" is specified.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--sleep
 
 type: float; default: 0
 
 How long to sleep between chunks while copying rows.  The time has micro-second
 precision, so you can specify fractions of seconds like \ ``0.1``\ .
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--tmp-table
 
 type: string
 
 Temporary table if \ ``--no-create-tmp-table``\  is specified.  If you specify
 \ ``--no-create-tmp-table``\ , then you must also specify this option to tell
 the tool which table to use as the temporary table.  The temporary table
 and the original table are renamed/swapped unless \ ``--no-rename-tables``\  is
 specified.
 
 The default behavior, when this option is not specified and
 \ ``--[no]create-tmp-tble``\  is true, is to create a temporary table named
 \ ``__tmp_TABLE``\  where \ ``TABLE``\  is the original table specified by the DSN
 on the command line.
 


--update-foreign-keys-method
 
 type: string
 
 Method for updating foreign key constraints in "--child-tables".  If
 "--child-tables" is specified, the tool will need to ensure that foreign
 key constraints in those tables continue to reference the original table
 after it is renamed and/or dropped.  This is necessary because when a parent
 table is renamed, MySQL automatically updates all child table
 foreign key constraints that reference the renamed table so that the rename
 does not break foreign key constraints.  This poses a problem for this tool.
 
 For example: if the table being altered is \ ``foo``\ , then \ ``foo``\  is renamed
 to \ ``__old_foo``\  when it is swapped with the "--tmp-table".
 Any foreign key references to \ ``foo``\  before it is swapped/renamed are renamed
 automatically by MySQL to \ ``__old_foo``\ .  We do not want this; we want those
 foreign key references to continue to reference \ ``foo``\ .
 
 There are currently two methods to solve this problem:
 
 
 rebuild_constraints
  
  Drop and re-add child table foreign key constraints to reference the new table.
  (The new table is the temporary table after being renamed/swapped.  To MySQL
  it's a new table because it does not know that it's a copy of the original
  table).  This method parses foreign key constraints referencing the original
  table from all child tables, drops them, then re-adds them referencing the
  new table.
  
  This method uses \ ``ALTER TABLE``\  which can by slow and blocking, but it is
  safer because the old table does not need to be dropped.  So if there's a
  problem with the new table and "--drop-old-table" was not specified,
  then the original table can be restored.
  
 
 
 drop_old_table
  
  Disable foreign key checks (FOREIGN_KEY_CHECKS=0) then drop the original table.
  This method bypasses MySQL's auto-renaming feature by disabling foreign key
  checks, dropping the original table, then renaming the temporary table with
  the same name.  Foreign key checks must be disabled to drop table because it is
  referenced by foreign key constraints.  Since the original table is not renamed,
  MySQL does not auto-rename references to it.  Then the temporary table is
  renamed to the same name so child table references are maintained.
  So this method requires "--drop-old-table".
  
  This method is faster and does not block, but it is less safe for two reasons.
  One, for a very short time (between dropping the original table and renaming the
  temporary table) the child tables reference a non-existent table.  Two, more
  importantly, if for some reason the temporary table was not copied correctly,
  didn't capture all changes, etc., the original table cannot be recovered
  because it was dropped.
  
 
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


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
 
 Database for the old and new table.
 


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
 


\* t
 
 dsn: table; copy: no
 
 Table to alter.
 


\* u
 
 dsn: user; copy: yes
 
 User for login if not current user.
 



***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-online-schema-change ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-online-schema-change <http://www.percona.com/bugs/pt-online-schema-change>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.
Include the following information in your bug report:


\* Complete command-line used to run the tool



\* Tool "--version"



\* MySQL version of all servers involved



\* Output from the tool including STDERR



\* Input files (log/dump/config files, etc.)



If possible, include debugging output by running the tool with \ ``PTDEBUG``\ ;
see "ENVIRONMENT".


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


*******
AUTHORS
*******


Baron Schwartz


***************
ACKNOWLEDGMENTS
***************


The "online schema change" concept was first implemented by Shlomi Noach
in his tool \ ``oak-online-alter-table``\ , part of
`http://code.google.com/p/openarkkit/ <http://code.google.com/p/openarkkit/>`_.  Then engineers at Facebook built
their version called \ ``OnlineSchemaChange.php``\  as explained by their blog
post: `http://tinyurl.com/32zeb86 <http://tinyurl.com/32zeb86>`_.  Searching for "online schema change"
will return other relevant pages about this concept.

This implementation, \ ``pt-online-schema-change``\ , is a hybrid of Shlomi's
and Facebook's approach.  Shlomi's code is a full-featured tool with command
line options, documentation, etc., but its continued development/support is
not assured.  Facebook's tool has certain technical advantages, but it's not
a full-featured tool; it's more a custom job by Facebook for Facebook.  And
neither of those tools is tested.  \ ``pt-online-schema-change``\  is a
full-featured, tested tool with stable development and support.

This tool was made possible by a generous client of Percona Inc.


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


This program is copyright 2011 Percona Inc.
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


pt-online-schema-change 1.0.1

