
##############
pt-slave-delay
##############

.. highlight:: perl


****
NAME
****


pt-slave-delay - Make a MySQL slave server lag behind its master.


********
SYNOPSIS
********


Usage: pt-slave-delay [OPTION...] SLAVE-HOST [MASTER-HOST]

pt-slave-delay starts and stops a slave server as needed to make it lag
behind the master.  The SLAVE-HOST and MASTER-HOST use DSN syntax, and
values are copied from the SLAVE-HOST to the MASTER-HOST if omitted.

To hold slavehost one minute behind its master for ten minutes:


.. code-block:: perl

    pt-slave-delay --delay 1m --interval 15s --run-time 10m slavehost



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-slave-delay is generally very low-risk.  It simply starts and stops the
replication SQL thread.  This might cause monitoring systems to think the slave
is having trouble.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-slave-delay <http://www.percona.com/bugs/pt-slave-delay>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


\ ``pt-slave-delay``\  watches a slave and starts and stops its replication SQL
thread as necessary to hold it at least as far behind the master as you
request.  In practice, it will typically cause the slave to lag between
"--delay" and "--delay"+"--interval" behind the master.

It bases the delay on binlog positions in the slave's relay logs by default,
so there is no need to connect to the master.  This works well if the IO
thread doesn't lag the master much, which is typical in most replication
setups; the IO thread lag is usually milliseconds on a fast network.  If your
IO thread's lag is too large for your purposes, \ ``pt-slave-delay``\  can also
connect to the master for information about binlog positions.

If the slave's I/O thread reports that it is waiting for the SQL thread to
free some relay log space, \ ``pt-slave-delay``\  will automatically connect to the
master to find binary log positions.  If "--ask-pass" and "--daemonize"
are given, it is possible that this could cause it to ask for a password while
daemonized.  In this case, it exits.  Therefore, if you think your slave might
encounter this condition, you should be sure to either specify
"--use-master" explicitly when daemonizing, or don't specify "--ask-pass".

The SLAVE-HOST and optional MASTER-HOST are both DSNs.  See "DSN OPTIONS".
Missing MASTER-HOST values are filled in with values from SLAVE-HOST, so you
don't need to specify them in both places.  \ ``pt-slave-delay``\  reads all normal
MySQL option files, such as ~/.my.cnf, so you may not need to specify username,
password and other common options at all.

\ ``pt-slave-delay``\  tries to exit gracefully by trapping signals such as Ctrl-C.
You cannot bypass "--[no]continue" with a trappable signal.


**********
PRIVILEGES
**********


pt-slave-delay requires the following privileges: PROCESS, REPLICATION CLIENT,
and SUPER.


******
OUTPUT
******


If you specify "--quiet", there is no output.  Otherwise, the normal output
is a status message consisting of a timestamp and information about what
\ ``pt-slave-delay``\  is doing: starting the slave, stopping the slave, or just
observing.


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
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
 runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
 binmode on STDOUT without the utf8 layer, and runs SET NAMES after
 connecting to MySQL.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--[no]continue
 
 default: yes
 
 Continue replication normally on exit.  After exiting, restart the slave's SQL
 thread with no UNTIL condition, so it will run as usual and catch up to the
 master.  This is enabled by default and works even if you terminate
 \ ``pt-slave-delay``\  with Control-C.
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX
 operating systems only.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--delay
 
 type: time; default: 1h
 
 How far the slave should lag its master.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--interval
 
 type: time; default: 1m
 
 How frequently \ ``pt-slave-delay``\  should check whether the slave needs to be
 started or stopped.
 


--log
 
 type: string
 
 Print all output to this file when daemonized.
 


--password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


--pid
 
 type: string
 
 Create the given PID file when daemonized.  The file contains the process
 ID of the daemonized instance.  The PID file is removed when the
 daemonized instance exits.  The program checks for the existence of the
 PID file when starting; if it exists and the process with the matching PID
 exists, the program exits.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--quiet
 
 short form: -q
 
 Don't print informational messages about operation.  See OUTPUT for details.
 


--run-time
 
 type: time
 
 How long \ ``pt-slave-delay``\  should run before exiting.  The default is to run
 forever.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--use-master
 
 Get binlog positions from master, not slave.  Don't trust the binlog positions
 in the slave's relay log.  Connect to the master and get binlog positions
 instead.  If you specify this option without giving a MASTER-HOST on the command
 line, \ ``pt-slave-delay``\  examines the slave's SHOW SLAVE STATUS to determine the
 hostname and port for connecting to the master.
 
 \ ``pt-slave-delay``\  uses only the MASTER_HOST and MASTER_PORT values from SHOW
 SLAVE STATUS for the master connection.  It does not use the MASTER_USER
 value.  If you want to specify a different username for the master than the
 one you use to connect to the slave, you should specify the MASTER-HOST option
 explicitly on the command line.
 


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

    PTDEBUG=1 pt-slave-delay ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-slave-delay <http://www.percona.com/bugs/pt-slave-delay>`_.

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


Sergey Zhuravlev and Baron Schwartz


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


This program is copyright 2007-2011 Sergey Zhuravle and Baron Schwartz,
2011 Percona Inc.
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

