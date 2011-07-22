
############
pt-heartbeat
############

.. highlight:: perl


****
NAME
****


pt-heartbeat - Monitor MySQL replication delay.


********
SYNOPSIS
********


Usage: pt-heartbeat [OPTION...] [DSN] --update|--monitor|--check|--stop

pt-heartbeat measures replication lag on a MySQL or PostgreSQL server.  You can
use it to update a master or monitor a replica.  If possible, MySQL connection
options are read from your .my.cnf file.

Start daemonized process to update test.heartbeat table on master:


.. code-block:: perl

   pt-heartbeat -D test --update -h master-server --daemonize


Monitor replication lag on slave:


.. code-block:: perl

   pt-heartbeat -D test --monitor -h slave-server
 
   pt-heartbeat -D test --monitor -h slave-server --dbi-driver Pg


Check slave lag once and exit (using optional DSN to specify slave host):


.. code-block:: perl

   pt-heartbeat -D test --check h=slave-server



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-heartbeat merely reads and writes a single record in a table.  It should be
very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-heartbeat <http://www.percona.com/bugs/pt-heartbeat>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-heartbeat is a two-part MySQL and PostgreSQL replication delay monitoring
system that measures delay by looking at actual replicated data.  This
avoids reliance on the replication mechanism itself, which is unreliable.  (For
example, \ ``SHOW SLAVE STATUS``\  on MySQL).

The first part is an "--update" instance of pt-heartbeat that connects to
a master and updates a timestamp ("heartbeat record") every "--interval"
seconds.  Since the heartbeat table may contain records from multiple
masters (see "MULTI-SLAVE HIERARCHY"), the server's ID (@@server_id) is
used to identify records.

The second part is a "--monitor" or "--check" instance of pt-heartbeat
that connects to a slave, examines the replicated heartbeat record from its
immediate master or the specified "--master-server-id", and computes the
difference from the current system time.  If replication between the slave and
the master is delayed or broken, the computed difference will be greater than
zero and potentially increase if "--monitor" is specified.

You must either manually create the heartbeat table on the master or use
"--create-table".  See "--create-table" for the proper heartbeat
table structure.  The \ ``MEMORY``\  storage engine is suggested, but not
required of course, for MySQL.

The heartbeat table must contain a heartbeat row.  By default, a heartbeat
row is inserted if it doesn't exist.  This feature can be disabled with the
"--[no]insert-heartbeat-row" option in case the database user does not
have INSERT privileges.

pt-heartbeat depends only on the heartbeat record being replicated to the slave,
so it works regardless of the replication mechanism (built-in replication, a
system such as Continuent Tungsten, etc).  It works at any depth in the
replication hierarchy; for example, it will reliably report how far a slave lags
its master's master's master.  And if replication is stopped, it will continue
to work and report (accurately!) that the slave is falling further and further
behind the master.

pt-heartbeat has a maximum resolution of 0.01 second.  The clocks on the
master and slave servers must be closely synchronized via NTP.  By default,
"--update" checks happen on the edge of the second (e.g. 00:01) and
"--monitor" checks happen halfway between seconds (e.g. 00:01.5).
As long as the servers' clocks are closely synchronized and replication
events are propagating in less than half a second, pt-heartbeat will report
zero seconds of delay.

pt-heartbeat will try to reconnect if the connection has an error, but will
not retry if it can't get a connection when it first starts.

The "--dbi-driver" option lets you use pt-heartbeat to monitor PostgreSQL
as well.  It is reported to work well with Slony-1 replication.


*********************
MULTI-SLAVE HIERARCHY
*********************


If the replication hierarchy has multiple slaves which are masters of
other slaves, like "master -> slave1 -> slave2", "--update" instances
can be ran on the slaves as well as the master.  The default heartbeat
table (see "--create-table") is keyed on the \ ``server_id``\  column, so
each server will update the row where \ ``server_id=@@server_id``\ .

For "--monitor" and "--check", if "--master-server-id" is not
specified, the tool tries to discover and use the slave's immediate master.
If this fails, or if you want monitor lag from another master, then you can
specify the "--master-server-id" to use.

For example, if the replication hierarchy is "master -> slave1 -> slave2"
with corresponding server IDs 1, 2 and 3, you can:


.. code-block:: perl

   pt-heartbeat --daemonize -D test --update -h master 
   pt-heartbeat --daemonize -D test --update -h slave1


Then check (or monitor) the replication delay from master to slave2:


.. code-block:: perl

   pt-heartbeat -D test --master-server-id 1 --check slave2


Or check the replication delay from slave1 to slave2:


.. code-block:: perl

   pt-heartbeat -D test --master-server-id 2 --check slave2


Stopping the "--update" instance one slave1 will not affect the instance
on master.


***********************
MASTER AND SLAVE STATUS
***********************


The default heartbeat table (see "--create-table") has columns for saving
information from \ ``SHOW MASTER STATUS``\  and \ ``SHOW SLAVE STATUS``\ .  These
columns are optional.  If any are present, their corresponding information
will be saved.


*******
OPTIONS
*******


Specify at least one of "--stop", "--update", "--monitor", or "--check".

"--update", "--monitor", and "--check" are mutually exclusive.

"--daemonize" and "--check" are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on STDOUT to
 utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET NAMES UTF8
 after connecting to MySQL.  Any other value sets binmode on STDOUT without the
 utf8 layer, and runs SET NAMES after connecting to MySQL.
 


--check
 
 Check slave delay once and exit.  If you also specify "--recurse", the
 tool will try to discover slave's of the given slave and check and print
 their lag, too.  The hostname or IP and port for each slave is printed
 before its delay.  "--recurse" only works with MySQL.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--create-table
 
 Create the heartbeat "--table" if it does not exist.
 
 This option causes the table specified by "--database" and "--table" to
 be created with the following MAGIC_create_heartbeat table definition:
 
 
 .. code-block:: perl
 
    CREATE TABLE heartbeat (
      ts                    varchar(26) NOT NULL,
      server_id             int unsigned NOT NULL PRIMARY KEY,
      file                  varchar(255) DEFAULT NULL,    -- SHOW MASTER STATUS
      position              bigint unsigned DEFAULT NULL, -- SHOW MASTER STATUS
      relay_master_log_file varchar(255) DEFAULT NULL,    -- SHOW SLAVE STATUS 
      exec_master_log_pos   bigint unsigned DEFAULT NULL  -- SHOW SLAVE STATUS
    );
 
 
 The heartbeat table requires at least one row.  If you manually create the
 heartbeat table, then you must insert a row by doing:
 
 
 .. code-block:: perl
 
    INSERT INTO heartbeat (ts, server_id) VALUES (NOW(), N);
 
 
 where \ ``N``\  is the server's ID; do not use @@server_id because it will replicate
 and slaves will insert their own server ID instead of the master's server ID.
 
 This is done automatically by "--create-table".
 
 A legacy version of the heartbeat table is still supported:
 
 
 .. code-block:: perl
 
    CREATE TABLE heartbeat (
      id int NOT NULL PRIMARY KEY,
      ts datetime NOT NULL
    );
 
 
 Legacy tables do not support "--update" instances on each slave
 of a multi-slave hierarchy like "master -> slave1 -> slave2".
 To manually insert the one required row into a legacy table:
 
 
 .. code-block:: perl
 
    INSERT INTO heartbeat (id, ts) VALUES (1, NOW());
 
 
 The tool automatically detects if the heartbeat table is legacy.
 
 See also "MULTI-SLAVE HIERARCHY".
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX operating systems only.
 


--database
 
 short form: -D; type: string
 
 The database to use for the connection.
 


--dbi-driver
 
 default: mysql; type: string
 
 Specify a driver for the connection; \ ``mysql``\  and \ ``Pg``\  are supported.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--file
 
 type: string
 
 Print latest "--monitor" output to this file.
 
 When "--monitor" is given, prints output to the specified file instead of to
 STDOUT.  The file is opened, truncated, and closed every interval, so it will
 only contain the most recent statistics.  Useful when "--daemonize" is given.
 


--frames
 
 type: string; default: 1m,5m,15m
 
 Timeframes for averages.
 
 Specifies the timeframes over which to calculate moving averages when
 "--monitor" is given.  Specify as a comma-separated list of numbers with
 suffixes.  The suffix can be s for seconds, m for minutes, h for hours, or d for
 days.  The size of the largest frame determines the maximum memory usage, as up
 to the specified number of per-second samples are kept in memory to calculate
 the averages.  You can specify as many timeframes as you like.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--[no]insert-heartbeat-row
 
 default: yes
 
 Insert a heartbeat row in the "--table" if one doesn't exist.
 
 The heartbeat "--table" requires a heartbeat row, else there's nothing
 to "--update", "--monitor", or "--check"!  By default, the tool will
 insert a heartbeat row if one is not already present.  You can disable this
 feature by specifying \ ``--no-insert-heartbeat-row``\  in case the database user
 does not have INSERT privileges.
 


--interval
 
 type: float; default: 1.0
 
 How often to update or check the heartbeat "--table".  Updates and checks
 begin on the first whole second then repeat every "--interval" seconds
 for "--update" and every "--interval" plus "--skew" seconds for
 "--monitor".
 
 For example, if at 00:00.4 an "--update" instance is started at 0.5 second
 intervals, the first update happens at 00:01.0, the next at 00:01.5, etc.
 If at 00:10.7 a "--monitor" instance is started at 0.05 second intervals
 with the default 0.5 second "--skew", then the first check happens at
 00:11.5 (00:11.0 + 0.5) which will be "--skew" seconds after the last update
 which, because the instances are checking at synchronized intervals, happened
 at 00:11.0.
 
 The tool waits for and begins on the first whole second just to make the
 interval calculations simpler.  Therefore, the tool could wait up to 1 second
 before updating or checking.
 
 The minimum (fastest) interval is 0.01, and the maximum precision is two
 decimal places, so 0.015 will be rounded to 0.02.
 
 If a legacy heartbeat table (see "--create-table") is used, then the
 maximum precision is 1s because the \ ``ts``\  column is type \ ``datetime``\ .
 


--log
 
 type: string
 
 Print all output to this file when daemonized.
 


--master-server-id
 
 type: string
 
 Calculate delay from this master server ID for "--monitor" or "--check".
 If not given, pt-heartbeat attempts to connect to the server's master and
 determine its server id.
 


--monitor
 
 Monitor slave delay continuously.
 
 Specifies that pt-heartbeat should check the slave's delay every second and
 report to STDOUT (or if "--file" is given, to the file instead).  The output
 is the current delay followed by moving averages over the timeframe given in
 "--frames".  For example,
 
 
 .. code-block:: perl
 
   5s [  0.25s,  0.05s,  0.02s ]
 
 


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
 


--print-master-server-id
 
 Print the auto-detected or given "--master-server-id".  If "--check"
 or "--monitor" is specified, specifying this option will print the
 auto-detected or given "--master-server-id" at the end of each line.
 


--recurse
 
 type: int
 
 Check slaves recursively to this depth in "--check" mode.
 
 Try to discover slave servers recursively, to the specified depth.  After
 discovering servers, run the check on each one of them and print the hostname
 (if possible), followed by the slave delay.
 
 This currently works only with MySQL.  See "--recursion-method".
 


--recursion-method
 
 type: string
 
 Preferred recursion method used to find slaves.
 
 Possible methods are:
 
 
 .. code-block:: perl
 
    METHOD       USES
    ===========  ================
    processlist  SHOW PROCESSLIST
    hosts        SHOW SLAVE HOSTS
 
 
 The processlist method is preferred because SHOW SLAVE HOSTS is not reliable.
 However, the hosts method is required if the server uses a non-standard
 port (not 3306).  Usually pt-heartbeat does the right thing and finds
 the slaves, but you may give a preferred method and it will be used first.
 If it doesn't find any slaves, the other methods will be tried.
 


--replace
 
 Use \ ``REPLACE``\  instead of \ ``UPDATE``\  for --update.
 
 When running in "--update" mode, use \ ``REPLACE``\  instead of \ ``UPDATE``\  to set
 the heartbeat table's timestamp.  The \ ``REPLACE``\  statement is a MySQL extension
 to SQL.  This option is useful when you don't know whether the table contains
 any rows or not.  It must be used in conjunction with --update.
 


--run-time
 
 type: time
 
 Time to run before exiting.
 


--sentinel
 
 type: string; default: /tmp/pt-heartbeat-sentinel
 
 Exit if this file exists.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--skew
 
 type: float; default: 0.5
 
 How long to delay checks.
 
 The default is to delay checks one half second.  Since the update happens as
 soon as possible after the beginning of the second on the master, this allows
 one half second of replication delay before reporting that the slave lags the
 master by one second.  If your clocks are not completely accurate or there is
 some other reason you'd like to delay the slave more or less, you can tweak this
 value.  Try setting the \ ``MKDEBUG``\  environment variable to see the effect this
 has.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--stop
 
 Stop running instances by creating the sentinel file.
 
 This should have the effect of stopping all running
 instances which are watching the same sentinel file.  If none of
 "--update", "--monitor" or "--check" is specified, \ ``pt-heartbeat``\ 
 will exit after creating the file.  If one of these is specified,
 \ ``pt-heartbeat``\  will wait the interval given by "--interval", then remove
 the file and continue working.
 
 You might find this handy to stop cron jobs gracefully if necessary, or to
 replace one running instance with another.  For example, if you want to stop
 and restart \ ``pt-heartbeat``\  every hour (just to make sure that it is restarted
 every hour, in case of a server crash or some other problem), you could use a
 \ ``crontab``\  line like this:
 
 
 .. code-block:: perl
 
   0 * * * * pt-heartbeat --update -D test --stop \
     --sentinel /tmp/pt-heartbeat-hourly
 
 
 The non-default "--sentinel" will make sure the hourly \ ``cron``\  job stops
 only instances previously started with the same options (that is, from the
 same \ ``cron``\  job).
 
 See also "--sentinel".
 


--table
 
 type: string; default: heartbeat
 
 The table to use for the heartbeat.
 
 Don't specify database.table; use "--database" to specify the database.
 
 See "--create-table".
 


--update
 
 Update a master's heartbeat.
 


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

    PTDEBUG=1 pt-heartbeat ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-heartbeat <http://www.percona.com/bugs/pt-heartbeat>`_.

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


Proven Scaling LLC, SixApart Ltd, Baron Schwartz, and Daniel Nichter


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


This program is copyright 2006 Proven Scaling LLC and Six Apart Ltd,
2007-2011 Percona Inc.
Feedback and improvements are welcome.

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

