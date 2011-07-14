
#############
pt-log-player
#############

.. highlight:: perl


****
NAME
****


pt-log-player - Replay MySQL query logs.


********
SYNOPSIS
********


Usage: pt-log-player [OPTION...] [DSN]

pt-log-player splits and plays slow log files.

Split slow.log on Thread_id into 16 session files, save in ./sessions:


.. code-block:: perl

   pt-log-player --split Thread_id --session-files 16 --base-dir ./sessions slow.log


Play all those sessions on host1, save results in ./results:


.. code-block:: perl

   pt-log-player --play ./sessions --base-dir ./results h=host1


Use pt-query-digest to summarize the results:


.. code-block:: perl

   pt-query-digest ./results/*



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

This tool is meant to load a server as much as possible, for stress-testing
purposes.  It is not designed to be used on production servers.

At the time of this release there is a bug which causes pt-log-player to
exceed max open files during "--split".

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-log-player <http://www.percona.com/bugs/pt-log-player>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-log-player does two things: it splits MySQL query logs into session files
and it plays (executes) queries in session files on a MySQL server.  Only
session files can be played; slow logs cannot be played directly without
being split.

A session is a group of queries from the slow log that all share a common
attribute, usually Thread_id.  The common attribute is specified with
"--split".  Multiple sessions are saved into a single session file.
See "--session-files", "--max-sessions", "--base-file-name" and
"--base-dir".  These session files are played with "--play".

pt-log-player will "--play" session files in parallel using N number of
"--threads".  (They're not technically threads, but we call them that
anyway.)  Each thread will play all the sessions in its given session files.
The sessions are played as fast as possible--there are no delays--because the
goal is to stress-test and load-test the server.  So be careful using this
script on a production server!

Each "--play" thread writes its results to a separate file.  These result
files are in slow log format so they can be aggregated and summarized with
pt-query-digest.  See "OUTPUT".


******
OUTPUT
******


Both "--split" and "--play" have two outputs: status messages printed to
STDOUT to let you know what the script is doing, and session or result files
written to separate files saved in "--base-dir".  You can suppress all
output to STDOUT for each with "--quiet", or increase output with
"--verbose".

The session files written by "--split" are simple text files containing
queries grouped into sessions.  For example:


.. code-block:: perl

   -- START SESSION 10
 
   use foo
 
   SELECT col FROM foo_tbl


The format of these session files is important: each query must be a single
line separated by a single blank line.  And the "-- START SESSION" comment
tells pt-log-player where individual sessions begin and end so that "--play"
can correctly fake Thread_id in its result files.

The result files written by "--play" are in slow log format with a minimal
header: the only attributes printed are Thread_id, Query_time and Schema.


*******
OPTIONS
*******


Specify at least one of "--play", "--split" or "--split-random".

"--play" and "--split" are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--ask-pass
 
 group: Play
 
 Prompt for a password when connecting to MySQL.
 


--base-dir
 
 type: string; default: ./
 
 Base directory for "--split" session files and "--play" result file.
 


--base-file-name
 
 type: string; default: session
 
 Base file name for "--split" session files and "--play" result file.
 
 Each "--split" session file will be saved as <base-file-name>-N.txt, where
 N is a four digit, zero-padded session ID.  For example: session-0003.txt.
 
 Each "--play" result file will be saved as <base-file-name>-results-PID.txt,
 where PID is the process ID of the executing thread.
 
 All files are saved in "--base-dir".
 


--charset
 
 short form: -A; type: string; group: Play
 
 Default character set.  If the value is utf8, sets Perl's binmode on STDOUT to
 utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET NAMES UTF8
 after connecting to MySQL.  Any other value sets binmode on STDOUT without the
 utf8 layer, and runs SET NAMES after connecting to MySQL.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.
 


--dry-run
 
 Print which processes play which session files then exit.
 


--filter
 
 type: string; group: Split
 
 Discard "--split" events for which this Perl code doesn't return true.
 
 This option only works with "--split".
 
 This option allows you to inject Perl code into the tool to affect how the
 tool runs.  Usually your code should examine \ ``$event``\  to decided whether
 or not to allow the event.  \ ``$event``\  is a hashref of attributes and values of
 the event being filtered.  Or, your code could add new attribute-value pairs
 to \ ``$event``\  for use by other options that accept event attributes as their
 value.  You can find an explanation of the structure of \ ``$event``\  at
 `http://code.google.com/p/maatkit/wiki/EventAttributes <http://code.google.com/p/maatkit/wiki/EventAttributes>`_.
 
 There are two ways to supply your code: on the command line or in a file.
 If you supply your code on the command line, it is injected into the following
 subroutine where \ ``$filter``\  is your code:
 
 
 .. code-block:: perl
 
     sub {
        MKDEBUG && _d('callback: filter');
        my( $event ) = shift;
        ( $filter ) && return $event;
     }
 
 
 Therefore you must ensure two things: first, that you correctly escape any
 special characters that need to be escaped on the command line for your
 shell, and two, that your code is syntactically valid when injected into
 the subroutine above.
 
 Here's an example filter supplied on the command line that discards
 events that are not SELECT statements:
 
 
 .. code-block:: perl
 
    --filter '$event->{arg} =~ m/^select/i'
 
 
 The second way to supply your code is in a file.  If your code is too complex
 to be expressed on the command line that results in valid syntax in the
 subroutine above, then you need to put the code in a file and give the file
 name as the value to "--filter".  The file should not contain a shebang
 (\ ``#!/usr/bin/perl``\ ) line.  The entire contents of the file is injected into
 the following subroutine:
 
 
 .. code-block:: perl
 
     sub {
        MKDEBUG && _d('callback: filter');
        my( $event ) = shift;
        $filter && return $event;
     }
 
 
 That subroutine is almost identical to the one above except your code is
 not wrapped in parentheses.  This allows you to write multi-line code like:
 
 
 .. code-block:: perl
 
     my $event_ok;
     if (...) {
        $event_ok = 1;
     }
     else {
        $event_ok = 0;
     }
     $event_ok
 
 
 Notice that the last line is not syntactically valid by itself, but it
 becomes syntactically valid when injected into the subroutine because it
 becomes:
 
 
 .. code-block:: perl
 
     $event_ok && return $event;
 
 
 If your code doesn't compile, the tool will die with an error.  Even if your
 code compiles, it may crash to tool during runtime if, for example, it tries
 a pattern match an undefined value.  No safeguards of any kind of provided so
 code carefully!
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string; group: Play
 
 Connect to host.
 


--iterations
 
 type: int; default: 1; group: Play
 
 How many times each thread should play all its session files.
 


--max-sessions
 
 type: int; default: 5000000; group: Split
 
 Maximum number of sessions to "--split".
 
 By default, \ ``pt-log-player``\  tries to split every session from the log file.
 For huge logs, however, this can result in millions of sessions.  This
 option causes only the first N number of sessions to be saved.  All sessions
 after this number are ignored, but sessions split before this number will
 continue to have their queries split even if those queries appear near the end
 of the log and after this number has been reached.
 


--only-select
 
 group: Play
 
 Play only SELECT and USE queries; ignore all others.
 


--password
 
 short form: -p; type: string; group: Play
 
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
 


--play
 
 type: string; group: Play
 
 Play (execute) session files created by "--split".
 
 The argument to play must be a comma-separated list of session files
 created by "--split" or a directory.  If the argument is a directory,
 ALL files in that directory will be played.
 


--port
 
 short form: -P; type: int; group: Play
 
 Port number to use for connection.
 


--print
 
 group: Play
 
 Print queries instead of playing them; requires "--play".
 
 You must also specify "--play" with "--print".  Although the queries
 will not be executed, "--play" is required to specify which session files to
 read.
 


--quiet
 
 short form: -q
 
 Do not print anything; disables "--verbose".
 


--[no]results
 
 default: yes
 
 Print "--play" results to files in "--base-dir".
 


--session-files
 
 type: int; default: 8; group: Split
 
 Number of session files to create with "--split".
 
 The number of session files should either be equal to the number of
 "--threads" you intend to "--play" or be an even multiple of
 "--threads".  This number is important for maximum performance because it:
 
 
 .. code-block:: perl
 
    * allows each thread to have roughly the same amount of sessions to play
    * avoids having to open/close many session files
    * avoids disk IO overhead by doing large sequential reads
 
 
 You may want to increase this number beyond "--threads" if each session
 file becomes too large.  For example, splitting a 20G log into 8 sessions
 files may yield roughly eight 2G session files.
 
 See also "--max-sessions".
 


--set-vars
 
 type: string; group: Play; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string; group: Play
 
 Socket file to use for connection.
 


--split
 
 type: string; group: Split
 
 Split log by given attribute to create session files.
 
 Valid attributes are any which appear in the log: Thread_id, Schema,
 etc.
 


--split-random
 
 group: Split
 
 Split log without an attribute, write queries round-robin to session files.
 
 This option, if specified, overrides "--split" and causes the log to be
 split query-by-query, writing each query to the next session file in round-robin
 style.  If you don't care about "sessions" and just want to split a lot into
 N many session files and the relation or order of the queries does not matter,
 then use this option.
 


--threads
 
 type: int; default: 2; group: Play
 
 Number of threads used to play sessions concurrently.
 
 Specifies the number of parallel processes to run.  The default is 2.  On
 GNU/Linux machines, the default is the number of times 'processor' appears in
 \ */proc/cpuinfo*\ .  On Windows, the default is read from the environment.
 In any case, the default is at least 2, even when there's only a single
 processor.
 
 See also "--session-files".
 


--type
 
 type: string; group: Split
 
 The type of log to "--split" (default slowlog).  The permitted types are
 
 
 binlog
  
  Split the output of running \ ``mysqlbinlog``\  against a binary log file.
  Currently, splitting binary logs does not always work well depending
  on what the binary logs contain.  Be sure to check the session files
  after splitting to ensure proper "OUTPUT".
  
  If the binary log contains row-based replication data, you need to run
  \ ``mysqlbinlog``\  with options \ ``--base64-output=decode-rows --verbose``\ ,
  else invalid statements will be written to the session files.
  
 
 
 genlog
  
  Split a general log file.
  
 
 
 slowlog
  
  Split a log file in any variation of MySQL slow-log format.
  
 
 


--user
 
 short form: -u; type: string; group: Play
 
 User for login if not current user.
 


--verbose
 
 short form: -v; cumulative: yes; default: 0
 
 Increase verbosity; can be specified multiple times.
 
 This option is disabled by "--quiet".
 


--version
 
 Show version and exit.
 


--wait-between-sessions
 
 type: array; default: 0; group: Play
 
 Not implemented yet.
 
 The wait time is given in seconds with microsecond precision and can be either
 a single value or a range.  A single value causes an exact wait; example:
 0.010 = wait 10 milliseconds.  A range causes a random wait between
 the given value times; example: 0.001,1 = random wait from 1 millisecond to
 1 second.
 


--[no]warnings
 
 default: no; group: Play
 
 Print warnings about SQL errors such as invalid queries to STDERR.
 



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


Visit `http://www.percona.com/software/ <http://www.percona.com/software/>`_ to download the latest release of
Percona Toolkit.  Or, to get the latest release from the command line:


.. code-block:: perl

    wget percona.com/latest/percona-toolkit/PKG


Replace \ ``PKG``\  with \ ``tar``\ , \ ``rpm``\ , or \ ``deb``\  to download the package in that
format.  You can also get individual tools from the latest release:


.. code-block:: perl

    wget percona.com/latest/percona-toolkit/TOOL


Replace \ ``TOOL``\  with the name of any tool.


***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-log-player ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-log-player <http://www.percona.com/bugs/pt-log-player>`_.

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


Daniel Nichter


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


This program is copyright 2008-2011 Percona Inc.
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

