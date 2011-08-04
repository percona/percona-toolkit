
##################
pt-deadlock-logger
##################

.. highlight:: perl


****
NAME
****


pt-deadlock-logger - Extract and log MySQL deadlock information.


********
SYNOPSIS
********


Usage: pt-deadlock-logger [OPTION...] SOURCE_DSN

pt-deadlock-logger extracts and saves information about the most recent deadlock
in a MySQL server.

Print deadlocks on SOURCE_DSN:


.. code-block:: perl

    pt-deadlock-logger SOURCE_DSN


Store deadlock information from SOURCE_DSN in test.deadlocks table on SOURCE_DSN
(source and destination are the same host):


.. code-block:: perl

    pt-deadlock-logger SOURCE_DSN --dest D=test,t=deadlocks


Store deadlock information from SOURCE_DSN in test.deadlocks table on DEST_DSN
(source and destination are different hosts):


.. code-block:: perl

    pt-deadlock-logger SOURCE_DSN --dest DEST_DSN,D=test,t=deadlocks


Daemonize and check for deadlocks on SOURCE_DSN every 30 seconds for 4 hours:


.. code-block:: perl

    pt-deadlock-logger SOURCE_DSN --dest D=test,t=deadlocks --daemonize --run-time 4h --interval 30s



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-deadlock-logger is a read-only tool unless you specify a "--dest" table.
In some cases polling SHOW INNODB STATUS too rapidly can cause extra load on the
server.  If you're using it on a production server under very heavy load, you
might want to set "--interval" to 30 seconds or more.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-deadlock-logger <http://www.percona.com/bugs/pt-deadlock-logger>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-deadlock-logger extracts deadlock data from a MySQL server.  Currently only
InnoDB deadlock information is available.  You can print the information to
standard output, store it in a database table, or both.  If neither
"--print" nor "--dest" are given, then the deadlock information is
printed by default.  If only "--dest" is given, then the deadlock
information is only stored.  If both options are given, then the deadlock
information is printed and stored.

The source host can be specified using one of two methods.  The first method is
to use at least one of the standard connection-related command line options:
"--defaults-file", "--password", "--host", "--port", "--socket"
or "--user".  These options only apply to the source host; they cannot be
used to specify the destination host.

The second method to specify the source host, or the optional destination host
using "--dest", is a DSN.  A DSN is a special syntax that can be either just
a hostname (like \ ``server.domain.com``\  or \ ``1.2.3.4``\ ), or a
\ ``key=value,key=value``\  string. Keys are a single letter:


.. code-block:: perl

   KEY MEANING
   === =======
   h   Connect to host
   P   Port number to use for connection
   S   Socket file to use for connection
   u   User for login if not current user
   p   Password to use when connecting
   F   Only read default options from the given file


If you omit any values from the destination host DSN, they are filled in with
values from the source host, so you don't need to specify them in both places.
\ ``pt-deadlock-logger``\  reads all normal MySQL option files, such as ~/.my.cnf, so
you may not need to specify username, password and other common options at all.


******
OUTPUT
******


You can choose which columns are output and/or saved to "--dest" with the
"--columns" argument.  The default columns are as follows:


server
 
 The (source) server on which the deadlock occurred.  This might be useful if
 you're tracking deadlocks on many servers.
 


ts
 
 The date and time of the last detected deadlock.
 


thread
 
 The MySQL thread number, which is the same as the connection ID in SHOW FULL
 PROCESSLIST.
 


txn_id
 
 The InnoDB transaction ID, which InnoDB expresses as two unsigned integers.  I
 have multiplied them out to be one number.
 


txn_time
 
 How long the transaction was active when the deadlock happened.
 


user
 
 The connection's database username.
 


hostname
 
 The connection's host.
 


ip
 
 The connection's IP address.  If you specify "--numeric-ip", this is
 converted to an unsigned integer.
 


db
 
 The database in which the deadlock occurred.
 


tbl
 
 The table on which the deadlock occurred.
 


idx
 
 The index on which the deadlock occurred.
 


lock_type
 
 The lock type the transaction held on the lock that caused the deadlock.
 


lock_mode
 
 The lock mode of the lock that caused the deadlock.
 


wait_hold
 
 Whether the transaction was waiting for the lock or holding the lock.  Usually
 you will see the two waited-for locks.
 


victim
 
 Whether the transaction was selected as the deadlock victim and rolled back.
 


query
 
 The query that caused the deadlock.
 



**************************
INNODB CAVEATS AND DETAILS
**************************


InnoDB's output is hard to parse and sometimes there's no way to do it right.

Sometimes not all information (for example, username or IP address) is included
in the deadlock information.  In this case there's nothing for the script to put
in those columns.  It may also be the case that the deadlock output is so long
(because there were a lot of locks) that the whole thing is truncated.

Though there are usually two transactions involved in a deadlock, there are more
locks than that; at a minimum, one more lock than transactions is necessary to
create a cycle in the waits-for graph.  pt-deadlock-logger prints the
transactions (always two in the InnoDB output, even when there are more
transactions in the waits-for graph than that) and fills in locks.  It prefers
waited-for over held when choosing lock information to output, but you can
figure out the rest with a moment's thought.  If you see one wait-for and one
held lock, you're looking at the same lock, so of course you'd prefer to see
both wait-for locks and get more information.  If the two waited-for locks are
not on the same table, more than two transactions were involved in the deadlock.


*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
 NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
 without the utf8 layer, and runs SET NAMES after connecting to MySQL.
 


--clear-deadlocks
 
 type: string
 
 Use this table to create a small deadlock.  This usually has the effect of
 clearing out a huge deadlock, which otherwise consumes the entire output of
 \ ``SHOW INNODB STATUS``\ .  The table must not exist.  pt-deadlock-logger will
 create it with the following MAGIC_clear_deadlocks structure:
 
 
 .. code-block:: perl
 
    CREATE TABLE test.deadlock_maker(a INT PRIMARY KEY) ENGINE=InnoDB;
 
 
 After creating the table and causing a small deadlock, the tool will drop the
 table again.
 


--[no]collapse
 
 Collapse whitespace in queries to a single space.  This might make it easier to
 inspect on the command line or in a query.  By default, whitespace is collapsed
 when printing with "--print", but not modified when storing to "--dest".
 (That is, the default is different for each action).
 


--columns
 
 type: hash
 
 Output only this comma-separated list of columns.  See "OUTPUT" for more
 details on columns.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--create-dest-table
 
 Create the table specified by "--dest".
 
 Normally the "--dest" table is expected to exist already.  This option
 causes pt-deadlock-logger to create the table automatically using the suggested
 table structure.
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX operating systems only.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--dest
 
 type: DSN
 
 DSN for where to store deadlocks; specify at least a database (D) and table (t).
 
 Missing values are filled in with the same values from the source host, so you
 can usually omit most parts of this argument if you're storing deadlocks on the
 same server on which they happen.
 
 By default, whitespace in the query column is left intact;
 use "--[no]collapse" if you want whitespace collapsed.
 
 The following MAGIC_dest_table is suggested if you want to store all the
 information pt-deadlock-logger can extract about deadlocks:
 
 
 .. code-block:: perl
 
   CREATE TABLE deadlocks (
     server char(20) NOT NULL,
     ts datetime NOT NULL,
     thread int unsigned NOT NULL,
     txn_id bigint unsigned NOT NULL,
     txn_time smallint unsigned NOT NULL,
     user char(16) NOT NULL,
     hostname char(20) NOT NULL,
     ip char(15) NOT NULL, -- alternatively, ip int unsigned NOT NULL
     db char(64) NOT NULL,
     tbl char(64) NOT NULL,
     idx char(64) NOT NULL,
     lock_type char(16) NOT NULL,
     lock_mode char(1) NOT NULL,
     wait_hold char(1) NOT NULL,
     victim tinyint unsigned NOT NULL,
     query text NOT NULL,
     PRIMARY KEY  (server,ts,thread)
   ) ENGINE=InnoDB
 
 
 If you use "--columns", you can omit whichever columns you don't want to
 store.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--interval
 
 type: time
 
 How often to check for deadlocks.  If no "--run-time" is specified,
 pt-deadlock-logger runs forever, checking for deadlocks at every interval.
 See also "--run-time".
 


--log
 
 type: string
 
 Print all output to this file when daemonized.
 


--numeric-ip
 
 Express IP addresses as integers.
 


--password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


--pid
 
 type: string
 
 Create the given PID file when daemonized.  The file contains the process ID of
 the daemonized instance.  The PID file is removed when the daemonized instance
 exits.  The program checks for the existence of the PID file when starting; if
 it exists and the process with the matching PID exists, the program exits.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--print
 
 Print results on standard output.  See "OUTPUT" for more.  By default,
 enables "--[no]collapse" unless you explicitly disable it.
 
 If "--interval" or "--run-time" is specified, only new deadlocks are
 printed at each interval.  A fingerprint for each deadlock is created using
 "--columns" server, ts and thread (even if those columns were not specified
 by "--columns") and if the current deadlock's fingerprint is different from
 the last deadlock's fingerprint, then it is printed.
 


--run-time
 
 type: time
 
 How long to run before exiting.  By default pt-deadlock-logger runs once,
 checks for deadlocks, and exits.  If "--run-time" is specified but
 no "--interval" is specified, a default 1 second interval will be used.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--tab
 
 Print tab-separated columns, instead of aligned.
 


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
 


\* t
 
 Table in which to store deadlock information.
 


\* u
 
 dsn: user; copy: yes
 
 User for login if not current user.
 



***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-deadlock-logger ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-deadlock-logger <http://www.percona.com/bugs/pt-deadlock-logger>`_.

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


Percona Toolkit v0.9.5 released 2011-08-04

