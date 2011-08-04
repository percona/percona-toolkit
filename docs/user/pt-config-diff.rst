
##############
pt-config-diff
##############

.. highlight:: perl


****
NAME
****


pt-config-diff - Diff MySQL configuration files and server variables.


********
SYNOPSIS
********


Usage: pt-config-diff [OPTION...] CONFIG CONFIG [CONFIG...]

pt-config-diff diffs MySQL configuration files and server variables.
CONFIG can be a filename or a DSN.  At least two CONFIG sources must be given.
Like standard Unix diff, there is no output if there are no differences.

Diff host1 config from SHOW VARIABLES against host2:


.. code-block:: perl

   pt-config-diff h=host1 h=host2


Diff config from [mysqld] section in my.cnf against host1 config:


.. code-block:: perl

   pt-config-diff /etc/my.cnf h=host1


Diff the [mysqld] section of two option files:


.. code-block:: perl

    pt-config-diff /etc/my-small.cnf /etc/my-large.cnf



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-config-diff reads MySQL's configuration and examines it and is thus very
low risk.

At the time of this release there are no known bugs that pose a serious risk.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-config-diff <http://www.percona.com/bugs/pt-config-diff>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-config-diff diffs MySQL configurations by examining the values of server
system variables from two or more CONFIG sources specified on the command
line.  A CONFIG source can be a DSN or a filename containing the output of
\ ``mysqld --help --verbose``\ , \ ``my_print_defaults``\ , \ ``SHOW VARIABLES``\ , or
an option file (e.g. my.cnf).

For each DSN CONFIG, pt-config-diff connects to MySQL and gets variables
and values by executing \ ``SHOW /\*!40103 GLOBAL\*/ VARIABLES``\ .  This is
an "active config" because it shows what server values MySQL is
actively (currently) running with.

Only variables that all CONFIG sources have are compared because if a
variable is not present then we cannot know or safely guess its value.
For example, if you compare an option file (e.g. my.cnf) to an active config
(i.e. SHOW VARIABLES from a DSN CONFIG), the option file will probably
only have a few variables, whereas the active config has every variable.
Only values of the variables present in both configs are compared.

Option file and DSN configs provide the best results.


******
OUTPUT
******


There is no output when there are no differences.  When there are differences,
pt-config-diff prints a report to STDOUT that looks similar to the following:


.. code-block:: perl

   2 config differences
   Variable                  my.master.cnf   my.slave.cnf
   ========================= =============== ===============
   datadir                   /tmp/12345/data /tmp/12346/data
   port                      12345           12346


Comparing MySQL variables is difficult because there are many variations and
subtleties across the many versions and distributions of MySQL.  When a
comparison fails, the tool prints a warning to STDERR, such as the following:


.. code-block:: perl

   Comparing log_error values (mysqld.log, /tmp/12345/data/mysqld.log)
   caused an error: Argument "/tmp/12345/data/mysqld.log" isn't numeric
   in numeric eq (==) at ./pt-config-diff line 2311.


Please report these warnings so the comparison functions can be improved.


***********
EXIT STATUS
***********


pt-config-diff exits with a zero exit status when there are no differences, and
1 if there are.


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
 first option on the command line.  (This option does not specify a CONFIG;
 it's equivalent to \ ``--defaults-file``\ .)
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX
 operating systems only.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--ignore-variables
 
 type: array
 
 Ignore, do not compare, these variables.
 


--password
 
 short form: -p; type: string
 
 Password to use for connection.
 


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
 


--[no]report
 
 default: yes
 
 Print the MySQL config diff report to STDOUT.  If you just want to check
 if the given configs are different or not by examining the tool's exit
 status, then specify \ ``--no-report``\  to suppress the report.
 


--report-width
 
 type: int; default: 78
 
 Truncate report lines to this many characters.  Since some variable values can
 be long, or when comparing multiple configs, it may help to increase the
 report width so values are not truncated beyond readability.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--user
 
 short form: -u; type: string
 
 MySQL user if not current user.
 


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
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-config-diff ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-config-diff <http://www.percona.com/bugs/pt-config-diff>`_.

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


Percona Toolkit v0.9.5 released 2011-08-04

