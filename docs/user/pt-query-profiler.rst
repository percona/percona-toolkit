
#################
pt-query-profiler
#################

.. highlight:: perl


****
NAME
****


pt-query-profiler - Execute SQL statements and print statistics, or measure activity caused by other processes.


********
SYNOPSIS
********


Usage: pt-query-profiler [OPTION...] [FILE...]

pt-query-profiler reads and executes queries, and prints statistics about
MySQL server load.  Connection options are read from MySQL option files.
If FILE is given, queries are read and executed from the file(s).  With no
FILE, or when FILE is -, read standard input.  If --external is specified,
lines in FILE are executed by the shell.  You must specify - if no FILE and
you want --external to read and execute from standard input.  Queries in
FILE must be terminated with a semicolon and separated by a blank line.

pt-query-profiler can profile the (semicolon-terminated, blank-line
separated) queries in a file:


.. code-block:: perl

    pt-query-profiler queries.sql
    cat queries.sql | pt-query-profiler
    pt-query-profiler -vv queries.sql
    pt-query-profiler -v --separate --only 2,5,6 queries.sql
    pt-query-profiler --tab queries.sql > results.csv


It can also just observe what happens in the server:


.. code-block:: perl

    pt-query-profiler --external


Or it can run shell commands from a file and measure the result:


.. code-block:: perl

    pt-query-profiler --external commands.txt
    pt-query-profiler --external - < commands.txt


Read "HOW TO INTERPRET" to learn what it all means.


*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-query-profiler is generally read-only and very low risk.  It will execute FLUSH TABLES if you specify "--flush".

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-query-profiler <http://www.percona.com/bugs/pt-query-profiler>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-query-profiler reads a file containing one or more SQL statements or shell
commands, executes them, and analyzes the output of SHOW STATUS afterwards.
It then prints statistics about how the batch performed.  For example, it can
show how many table scans the batch caused, how many page reads, how many
temporary tables, and so forth.

All command-line arguments are optional, but you must either specify a file
containing the batch to profile as the last argument, or specify that you're
profiling an external program with the "--external" option, or provide
input to STDIN.

If the file contains multiple statements, they must be separated by blank
lines.  If you don't do that, pt-query-profiler won't be able to split the
file into individual queries, and MySQL will complain about syntax errors.

If the MySQL server version is before 5.0.2, you should make sure the server
is completely unused before trying to profile a batch.  Prior to this version,
SHOW STATUS showed only global status variables, so other queries will
interfere and produce false results.  pt-query-profiler will try to detect
if anything did interfere, but there can be no guarantees.

Prior to MySQL 5.0.2, InnoDB status variables are not available, and prior to
version 5.0.3, InnoDB row lock status variables are not available.
pt-query-profiler will omit any output related to these variables if they're not
available.

For more information about SHOW STATUS, read the relevant section of the MySQL
manual at
`http://dev.mysql.com/doc/en/server-status-variables.html <http://dev.mysql.com/doc/en/server-status-variables.html>`_


****************
HOW TO INTERPRET
****************


TAB-SEPARATED OUTPUT
====================


If you specify "--tab", you will get the raw output of SHOW STATUS in
tab-separated format, convenient for opening with a spreadsheet.  This is not
the default output, but it's so much easier to describe that I'll cover it
first.


\*
 
 Most of the command-line options for controlling verbosity and such are
 ignored in --tab mode.
 


\*
 
 The variable names you see in MySQL, such as 'Com_select', are kept --
 there are no euphimisms, so you have to know your MySQL variables.
 


\*
 
 The columns are Variable_name, Before, After1...AfterN, Calibration.
 The Variable_name column is just what it sounds like.  Before is the result
 from the first run of SHOW STATUS.  After1, After2, etc are the results of
 running SHOW STATUS after each query in the batch.  Finally, the last column
 is the result of running SHOW STATUS just after the last AfterN column, so you
 can see how much work SHOW STATUS itself causes.
 


\*
 
 If you specify "--verbose", output includes every variable
 pt-query-profiler measures.  If not (default) it only includes variables where
 there was some difference from one column to the next.
 



NORMAL OUTPUT
=============


If you don't specify --tab, you'll get a report formatted for human
readability.  This is the default output format.

pt-query-profiler can output a lot of information, as you've seen if you
ran the examples in the "SYNOPSIS".  What does it all mean?

First, there are two basic groups of information you might see: per-query and
summary.  If your batch contains only one query, these will be the same and
you'll only see the summary.  You can recognize the difference by looking for
centered, all-caps, boxed-in section headers.  Externally profiled commands will
have EXTERNAL, individually profiled queries will have QUERY, and summary will
say SUMMARY.

Next, the information in each section is grouped into subsections, headed by
an underlined title.  Each of these sections has varying information in it.
Which sections you see depends on command-line arguments and your MySQL
version.  I'll explain each section briefly.  If you really want to know where
the numbers come from, read
`http://dev.mysql.com/doc/en/server-status-variables.html <http://dev.mysql.com/doc/en/server-status-variables.html>`_.

You need to understand which numbers are insulated from other queries and
which are not.  This depends on your MySQL version.  Version 5.0.2 introduced
the concept of session status variables, so you can see information about only
your own connection.  However, many variables aren't session-ized, so when you
have MySQL 5.0.2 or greater, you will actually see a mix of session and global
variables.  That means other queries happening at the same time will pollute
some of your results.  If you have MySQL versions older than 5.0.2, you won't
have ANY connection-specific stats, so your results will be polluted by other
queries no matter what.  Because of the mixture of session and global
variables, by far the best way to profile is on a completely quiet server
where nothing else is interfering with your results.

While explaining the results in the sections that follow, I'll refer to a
value as "protected" if it comes from a session-specific variable and can be
relied upon to be accurate even on a busy server.  Just keep in mind, if
you're not using MySQL 5.0.2 or newer, your results will be inaccurate unless
you're running against a totally quiet server, even if I label it as
"protected."


Overall stats
=============


This section shows the overall elapsed time for the query, as measured by
Perl, and the optimizer cost as reported by MySQL.

If you're viewing separate query statistics, this is all you'll see.  If
you're looking at a summary, you'll also see a breakdown of the questions the
queries asked the server.

The execution time is not totally reliable, as it includes network round-trip
time, Perl's own execution time, and so on.  However, on a low-latency
network, this should be fairly negligible, giving you a reasonable measure of
the query's time, especially for queries longer than a few tenths of a second.

The optimizer cost comes from the Last_query_cost variable, and is protected
from other connections in MySQL 5.0.7 and greater.  It is not available before
5.0.1.

The total number of questions is not protected, but the breakdown of
individual question types is, because it comes from the \ ``Com_``\  status variables.


Table and index accesses
========================


This section shows you information about the batch's table and index-level
operations (as opposed to row-level operations, which will be in the next
section).  The "Table locks acquired" and "Temp files" values are unprotected,
but everything else in this section is protected.

The "Potential filesorts" value is calculated as the number of times a query had
both a scan sort (Sort_scan) and created a temporary table (Created_tmp_tables).
There is no Sort_filesort or similar status value, so it's a best guess at
whether a query did a filesort.  It should be fairly accurate.

If you specified "--allow-cache", you'll see statistics on the query cache.
These are unprotected.


Row operations
==============


These values are all about the row-level operations your batch caused.  For
example, how many rows were inserted, updated, or deleted.  You'll also see
row-level index access statistics, such as how many times the query sought and
read the next entry in an index.

Depending on your MySQL version, you'll either see one or two columns of
information in this section.  The one headed "Handler" is all from the
\ ``Handler_``\  variables, and those statistics are protected.  If your MySQL version
supports it, you'll also see a column headed "InnoDB," which is unprotected.


I/O Operations
==============


This section gives information on I/O operations your batch caused, both in
memory and on disk.  Unless you have MySQL 5.0.2 or greater, you'll only see
information on the key cache.  Otherwise, you'll see a lot of information on
InnoDB's I/O operations as well, such as how many times the query was able to
satisfy a read from the buffer pool and how many times it had to go to the
disk.

None of the information in this section is protected.


InnoDB Data Operations
======================


This section only appears when you're querying MySQL 5.0.2 or newer.  None of
the information is protected.  You'll see statistics about how many pages were
affected, how many operations took place, and how many bytes were affected.



*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--allow-cache
 
 Let MySQL query cache cache the queries executed.
 
 By default this is disabled.  When enabled, cache profiling information is added
 to the printout.  See `http://dev.mysql.com/doc/en/query-cache.html <http://dev.mysql.com/doc/en/query-cache.html>`_ for more
 information about the query cache.
 


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--[no]calibrate
 
 default: yes
 
 Try to compensate for \ ``SHOW STATUS``\ .
 
 Measure and compensate for the "cost of observation" caused by running SHOW
 STATUS.  Only works reliably on a quiet server; on a busy server, other
 processes can cause the calibration to be wrong.
 


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
 


--database
 
 short form: -D; type: string
 
 Database to use for connection.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--external
 
 Calibrate, then pause while an external program runs.
 
 This is typically useful while you run an external program.  When you press
 [enter] pt-query-profiler will stop sleeping and take another measurement, then
 print statistics as usual.
 
 When there is a filename on the command line, pt-query-profiler executes
 each line in the file as a shell command.  If you give - as the filename,
 pt-query-profiler reads from STDIN.
 
 Output from shell commands is printed to STDOUT and terminated with __BEGIN__,
 after which pt-query-profiler prints its own output.
 


--flush
 
 cumulative: yes
 
 Flush tables.  Specify twice to do between every query.
 
 Calls FLUSH TABLES before profiling.  If you are executing queries from a
 batch file, specifying --flush twice will cause pt-query-profiler to call
 FLUSH TABLES between every query, not just once at the beginning.  Default is
 not to flush at all. See `http://dev.mysql.com/doc/en/flush.html <http://dev.mysql.com/doc/en/flush.html>`_ for more
 information.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--[no]innodb
 
 default: yes
 
 Show InnoDB statistics.
 


--only
 
 type: hash
 
 Only show statistics for this comma-separated list of queries or commands.
 


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
 


--separate
 
 Print stats separately for each query.
 
 The default is to show only the summary of the entire batch.  See also
 "--verbose".
 


--[no]session
 
 default: yes
 
 Use session \ ``SHOW STATUS``\  and \ ``SHOW VARIABLES``\ .
 
 Disabled if the server version doesn't support it.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--tab
 
 Print tab-separated values instead of whitespace-aligned columns.
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


--verbose
 
 short form: -v; cumulative: yes; default: 0
 
 Verbosity; specify multiple times for more detailed output.
 
 When "--tab" is given, prints variables that don't change.  Otherwise
 increasing the level of verbosity includes extra sections in the output.
 


--verify
 
 Verify nothing else is accessing the server.
 
 This is a weak verification; it simply calibrates twice (see
 "--[no]calibrate") and verifies that the cost of observation remains
 constant.
 


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

    PTDEBUG=1 pt-query-profiler ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-query-profiler <http://www.percona.com/bugs/pt-query-profiler>`_.

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


Baron Schwartz and Bart van Bragt


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

