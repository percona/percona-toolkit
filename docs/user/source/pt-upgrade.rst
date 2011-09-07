.. program:: pt-upgrade

=======================
 :program:`pt-upgrade`
=======================

.. highlight:: perl


NAME
====

 :program:`pt-upgrade` - Execute queries on multiple servers and check for differences.


SYNOPSIS
========


Usage
-----

::

   pt-upgrade [OPTION...] DSN [DSN...] [FILE]

:program:`pt-upgrade` compares query execution on two hosts by executing queries in the
given file (or ``STDIN`` if no file given) and examining the results, errors,
warnings, etc.produced on each.

Execute and compare all queries in slow.log on host1 to host2:


.. code-block:: perl

   pt-upgrade slow.log h=host1 h=host2


Use pt-query-digest to get, execute and compare queries from tcpdump:


.. code-block:: perl

   tcpdump -i eth0 port 3306 -s 65535  -x -n -q -tttt     \
     | pt-query-digest --type tcpdump --no-report --print \
     | :program:`pt-upgrade` h=host1 h=host2


Compare only query times on host1 to host2 and host3:


.. code-block:: perl

   pt-upgrade slow.log h=host1 h=host2 h=host3 --compare query_times


Compare a single query, no slowlog needed:


.. code-block:: perl

   pt-upgrade h=host1 h=host2 --query 'SELECT * FROM db.tbl'



RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-upgrade` is a read-only tool that is meant to be used on non-production
servers.  It executes the SQL that you give it as input, which could cause
undesired load on a production server.

At the time of this release, there is a bug that causes the tool to crash,
and a bug that causes a deadlock.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-upgrade <http://www.percona.com/bugs/pt-upgrade>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-upgrade` executes queries from slowlogs on one or more |MySQL| server to find
differences in query time, warnings, results, and other aspects of the querys'
execution.  This helps evaluate upgrades, migrations and configuration
changes.  The comparisons specified by :option:`--compare` determine what
differences can be found.  A report is printed which outlines all the
differences found; see "OUTPUT" below.

The first DSN (host) specified on the command line is authoritative; it defines
the results to which the other DSNs are compared.  You can "compare" only one
host, in which case there will be no differences but the output can be saved
to be diffed later against the output of another single host "comparison".

At present, :program:`pt-upgrade` only reads slowlogs.  Use \ ``pt-query-digest --print``\  to
transform other log formats to slowlog.

DSNs and slowlog files can be specified in any order.  :program:`pt-upgrade` will
automatically determine if an argument is a DSN or a slowlog file.  If no
slowlog files are given and :option:`--query` is not specified then :program:`pt-upgrade`
will read from \ ````STDIN````\ .


OUTPUT
======


TODO


OPTIONS
=======


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


.. option:: --ask-pass
 
 Prompt for a password when connecting to |MySQL|.
 


.. option:: --base-dir
 
 type: string; default: /tmp
 
 Save outfiles for the \ ``rows``\  comparison method in this directory.
 
 See the \ ``rows``\  :option:`--compare-results-method`.
 


.. option:: --charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets *Perl* 's binmode on
 ``STDOUT`` to utf8, passes the mysql_enable_utf8 option to ``DBD::mysql``, and
 runs SET NAMES UTF8 after connecting to |MySQL|.  Any other value sets
 binmode on ``STDOUT`` without the utf8 layer, and runs SET NAMES after
 connecting to |MySQL|.
 


.. option:: --[no]clear-warnings
 
 default: yes
 
 Clear warnings before each warnings comparison.
 
 If comparing warnings (:option:`--compare` includes \ ``warnings``\ ), this option
 causes :program:`pt-upgrade` to execute a successful \ ``SELECT``\  statement which clears
 any warnings left over from previous queries.  This requires a current
 database that :program:`pt-upgrade` usually detects automatically, but in some cases
 it might be necessary to specify :option:`--temp-database`.  If :program:`pt-upgrade` can't auto-detect the current database, it will create a temporary table in the
 :option:`--temp-database` called \ ``mk_upgrade_clear_warnings``\ .
 


.. option:: --clear-warnings-table
 
 type: string
 
 Execute \ ``SELECT FROM ... LIMIT 1``\  from this table to clear warnings.
 


.. option:: --compare
 
 type: Hash; default: query_times,results,warnings
 
 What to compare for each query executed on each host.
 
 Comparisons determine differences when the queries are executed on the hosts.
 More comparisons enable more differences to be detected.  The following
 comparisons are available:
 
 
  * `` query_times``
  
  Compare query execution times.  If this comparison is disabled, the queries
  are still executed so that other comparisons will work, but the query time
  attributes are removed from the events.
  
 
 
  * `` results``
  
  Compare result sets to find differences in rows, columns, etc.
  
  What differences can be found depends on the :option:`--compare-results-method` used.
  
 
 
  * `` warnings``
  
  Compare warnings from \ ``SHOW WARNINGS``\ .  Requires at least |MySQL| 4.1.
  
 
 


.. option:: --compare-results-method
 
 type: string; default: CHECKSUM; group: Comparisons
 
 Method to use for :option:`--compare` \ ``results``\ .  This option has no effect
 if \ ``--no-compare-results``\  is given.
 
 Available compare methods (case-insensitive):
 
 
  * `` CHECKSUM``
  
  Do \ ``CREATE TEMPORARY TABLE \`mk_upgrade\` AS query``\  then
  \ ``CHECKSUM TABLE \`mk_upgrade\```\ .  This method is fast and simple but in
  rare cases might it be inaccurate because the |MySQL| manual says:
  
  
  .. code-block:: perl
  
     [The] fact that two tables produce the same checksum does I<not> mean that
     the tables are identical.
  
  
  Requires at least |MySQL| 4.1.
  
 
 
  * `` rows``
  
  Compare rows one-by-one to find differences.  This method has advantages
  and disadvantages.  Its disadvantages are that it may be slower and it
  requires writing and reading outfiles from disk.  Its advantages are that
  it is universal (works for all versions of |MySQL|), it doesn't alter the query
  in any way, and it can find column value differences.
  
  The \ ``rows``\  method works as follows:
  
  
  .. code-block:: perl
  
     1. Rows from each host are compared one-by-one.
     2. If no differences are found, comparison stops, else...
     3. All remain rows (after the point where they begin to differ)
        are written to outfiles.
     4. The outfiles are loaded into temporary tables with
        C<LOAD DATA LOCAL INFILE>.
     5. The temporary tables are analyzed to determine the differences.
  
  
  The outfiles are written to the :option:`--base-dir`.
  
 
 


.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


.. option:: --continue-on-error
 
 Continue working even if there is an error.
 


.. option:: --convert-to-select
 
 Convert non-SELECT statements to SELECTs and compare.
 
 By default non-SELECT statements are not allowed.  This option causes
 non-SELECT statments (like UPDATE, INSERT and DELETE) to be converted
 to SELECT statements, executed and compared.
 
 For example, \ ``DELETE col FROM tbl WHERE id=1``\  is converted to
 \ ``SELECT col FROM tbl WHERE id=1``\ .
 


.. option:: --daemonize
 
 Fork to the background and detach from the shell.  POSIX
 operating systems only.
 


.. option:: --explain-hosts
 
 Print connection information and exit.
 


.. option:: --filter
 
 type: string
 
 Discard events for which this *Perl*  code doesn't return true.
 
 This option is a string of *Perl*  code or a file containing *Perl*  code that gets
 compiled into a subroutine with one argument: $event.  This is a hashref.
 If the given value is a readable file, then :program:`pt-upgrade` reads the entire
 file and uses its contents as the code.  The file should not contain
 a shebang (#!/usr/bin/perl) line.
 
 If the code returns true, the chain of callbacks continues; otherwise it ends.
 The code is the last statement in the subroutine other than \ ``return $event``\ . 
 The subroutine template is:
 
 
 .. code-block:: perl
 
    sub { $event = shift; filter && return $event; }
 
 
 Filters given on the command line are wrapped inside parentheses like like
 \ ``( filter )``\ .  For complex, multi-line filters, you must put the code inside
 a file so it will not be wrapped inside parentheses.  Either way, the filter
 must produce syntactically valid code given the template.  For example, an
 if-else branch given on the command line would not be valid:
 
 
 .. code-block:: perl
 
    --filter 'if () { } else { }'  # WRONG
 
 
 Since it's given on the command line, the if-else branch would be wrapped inside
 parentheses which is not syntactically valid.  So to accomplish something more
 complex like this would require putting the code in a file, for example
 filter.txt:
 
 
 .. code-block:: perl
 
    my $event_ok; if (...) { $event_ok=1; } else { $event_ok=0; } $event_ok
 
 
 Then specify \ ``--filter filter.txt``\  to read the code from filter.txt.
 
 If the filter code won't compile, :program:`pt-upgrade` will die with an error.
 If the filter code does compile, an error may still occur at runtime if the
 code tries to do something wrong (like pattern match an undefined value).
 :program:`pt-upgrade` does not provide any safeguards so code carefully!
 
 An example filter that discards everything but SELECT statements:
 
 
 .. code-block:: perl
 
    --filter '$event->{arg} =~ m/^select/i'
 
 
 This is compiled into a subroutine like the following:
 
 
 .. code-block:: perl
 
    sub { $event = shift; ( $event->{arg} =~ m/^select/i ) && return $event; }
 
 
 It is permissible for the code to have side effects (to alter $event).
 
 You can find an explanation of the structure of $event at
 `http://code.google.com/p/maatkit/wiki/EventAttributes <http://code.google.com/p/maatkit/wiki/EventAttributes>`_.
 


.. option:: --fingerprints
 
 Add query fingerprints to the standard query analysis report.  This is mostly
 useful for debugging purposes.
 


.. option:: --float-precision
 
 type: int
 
 Round float, double and decimal values to this many places.
 
 This option helps eliminate false-positives caused by floating-point
 imprecision.
 


.. option:: --help
 
 Show help and exit.
 


.. option:: --host
 
 short form: -h; type: string
 
 Connect to host.
 


.. option:: --iterations
 
 type: int; default: 1
 
 How many times to iterate through the collect-and-report cycle.  If 0, iterate
 to infinity.  See also --run-time.
 


.. option:: --limit
 
 type: string; default: 95%:20
 
 Limit output to the given percentage or count.
 
 If the argument is an integer, report only the top N worst queries.  If the
 argument is an integer followed by the \ ``%``\  sign, report that percentage of the
 worst queries.  If the percentage is followed by a colon and another integer,
 report the top percentage or the number specified by that integer, whichever
 comes first.
 


.. option:: --log
 
 type: string
 
 Print all output to this file when daemonized.
 


.. option:: --max-different-rows
 
 type: int; default: 10
 
 Stop comparing rows for \ ``--compare-results-method rows``\  after this many
 differences are found.
 


.. option:: --order-by
 
 type: string; default: differences:sum
 
 Sort events by this attribute and aggregate function.
 


.. option:: --password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


.. option:: --pid
 
 type: string
 
 Create the given PID file when daemonized.  The file contains the process
 ID of the daemonized instance.  The PID file is removed when the
 daemonized instance exits.  The program checks for the existence of the
 PID file when starting; if it exists and the process with the matching PID
 exists, the program exits.
 


.. option:: --port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


.. option:: --query
 
 type: string
 
 Execute and compare this single query; ignores files on command line.
 
 This option allows you to supply a single query on the command line.  Any
 slowlogs also specified on the command line are ignored.
 


.. option:: --reports
 
 type: Hash; default: queries,differences,errors,statistics
 
 Print these reports.  Valid reports are queries, differences, errors, and
 statistics.
 
 See "OUTPUT" for more information on the various parts of the report.
 


.. option:: --run-time
 
 type: time
 
 How long to run before exiting.  The default is to run forever (you can
 interrupt with CTRL-C).
 


.. option:: --set-vars
 
 type: string; default: wait_timeout=10000,query_cache_type=0
 
 Set these |MySQL| variables.  Immediately after connecting to |MySQL|, this
 string will be appended to SET and executed.
 


.. option:: --shorten
 
 type: int; default: 1024
 
 Shorten long statements in reports.
 
 Shortens long statements, replacing the omitted portion with a \ ``/\*... omitted
 ...\*/``\  comment.  This applies only to the output in reports.  It prevents a
 large statement from causing difficulty in a report.  The argument is the
 preferred length of the shortened statement.  Not all statements can be
 shortened, but very large INSERT and similar statements often can; and so
 can IN() lists, although only the first such list in the statement will be
 shortened.
 
 If it shortens something beyond recognition, you can find the original statement
 in the log, at the offset shown in the report header (see "OUTPUT").
 


.. option:: --socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


.. option:: --temp-database
 
 type: string
 
 Use this database for creating temporary tables.
 
 If given, this database is used for creating temporary tables for the
 results comparison (see :option:`--compare`).  Otherwise, the current
 database (from the last event that specified its database) is used.
 


.. option:: --temp-table
 
 type: string; default: mk_upgrade
 
 Use this table for checksumming results.
 


.. option:: --user
 
 short form: -u; type: string
 
 User for login if not current user.
 


.. option:: --version
 
 Show version and exit.
 


.. option:: --zero-query-times
 
 Zero the query times in the report.
 



DSN OPTIONS
===========


These DSN options are used to create a DSN.  Each option is given like
\ ``option=value``\ .  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the \ ``=``\ , and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the percona-toolkit manpage for full details.


  * ``A``
 
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

    PTDEBUG=1 :program:`pt-upgrade` ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-upgrade <http://www.percona.com/bugs/pt-upgrade>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.


AUTHORS
=======


*Daniel Nichter*


COPYRIGHT, LICENSE, AND WARRANTY
================================


This program is copyright 2009-2011 Percona Inc.
Feedback and improvements are welcome.


VERSION
=======

:program:`pt-upgrade` 1.0.1

