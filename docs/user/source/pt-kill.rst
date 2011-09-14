.. program:: pt-kill

====================
 :program:`pt-kill`
====================

.. highlight:: perl


NAME
====

 :program:`pt-kill` - Kill |MySQL| queries that match certain criteria.


SYNOPSIS
========


Usage
-----

::

   pt-kill [OPTION]... [FILE...]

:program:`pt-kill` kills |MySQL| connections.  :program:`pt-kill` connects to |MySQL| and gets queries from SHOW PROCESSLIST if no FILE is given.  Else, it reads queries from one or more FILE which contains the output of SHOW PROCESSLIST.  If FILE is -, :program:`pt-kill` reads from ``STDIN``.

Kill queries running longer than 60s:


.. code-block:: perl

   pt-kill --busy-time 60 --kill


Print, do not kill, queries running longer than 60s:


.. code-block:: perl

   pt-kill --busy-time 60 --print


Check for sleeping processes and kill them all every 10s:


.. code-block:: perl

   pt-kill --match-command Sleep --kill --victims all --interval 10


Print all login processes:


.. code-block:: perl

   pt-kill --match-state login --print --victims all


See which queries in the processlist right now would match:


.. code-block:: perl

    mysql -e "SHOW PROCESSLIST" | pt-kill --busy-time 60 --print



RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-kill` is designed to kill queries if you use the :option:`--kill` option is given, and that might disrupt your database's users, of course.  You should test with
the :option:`--print` option, which is safe, if you're unsure what the tool will do.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-kill <http://www.percona.com/bugs/pt-kill>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-kill` captures queries from SHOW PROCESSLIST, filters them, and then either kills or prints them.  This is also known as a "slow query sniper" in some
circles.  The idea is to watch for queries that might be consuming too many
resources, and kill them.

For brevity, we talk about killing queries, but they may just be printed (or some other future action) depending on what options are given.

Normally :program:`pt-kill` connects to |MySQL| to get queries from SHOW PROCESSLIST.
Alternatively, it can read SHOW PROCESSLIST output from files.  In this case, :program:`pt-kill` does not connect to |MySQL| and :option:`--kill` has no effect.  You should use :option:`--print` instead when reading files.  The ability to read a file (or
- for ``STDIN``) allows you to capture ``SHOW PROCESSLIST`` and test it later with :program:`pt-kill` to make sure that your matches kill the proper queries.  There are a
lot of special rules to follow, such as "don't kill replication threads," so be careful to not kill something important!

Two important options to know are :option:`--busy-time" and "--victims`.
First, whereas most match/filter options match their corresponding value from
SHOW PROCESSLIST (e.g. :option:`--match-command` matches a query's Command value),
the Time value is matched by :option:`--busy-time".  See also "--interval`.

Second, :option:`--victims` controls which matching queries from each class are
killed.  By default, the matching query with the highest Time value is killed
(the oldest query).  See the next section, "GROUP, MATCH AND KILL",
for more details.

Usually you need to specify at least one \ ``--match``\  option, else no
queries will match.  Or, you can specify :option:`--match-all` to match all queries
that aren't ignored by an \ ``--ignore``\  option.

:program:`pt-kill` is a work in progress, and there is much more it could do.


GROUP, MATCH AND KILL
=====================


Queries pass through several steps to determine which exactly will be killed
(or printed--whatever action is specified).  Understanding these steps will
help you match precisely the queries you want.

The first step is grouping queries into classes.  The :option:`--group-by` option
controls grouping.  By default, this option has no value so all queries are
grouped into one, big default class.  All types of matching and filtering
(the next step) are applied per-class.  Therefore, you may need to group
queries in order to match/filter some classes but not others.

The second step is matching.  Matching implies filtering since if a query
doesn't match some criteria, it is removed from its class.
Matching happens for each class.  First, queries are filtered from their
class by the various ``Query Matches`` options like :option:`--match-user`.
Then, entire classes are filtered by the various ``Class Matches`` options
like :option:`--query-count`.

The third step is victim selection, that is, which matching queries in each
class to kill.  This is controlled by the :option:`--victims` option.  Although
many queries in a class may match, you may only want to kill the oldest
query, or all queries, etc.

The forth and final step is to take some action on all matching queries
from all classes.  The ``Actions``  options specify which actions will be
taken.  At this step, there are no more classes, just a single list of
queries to kill, print, etc.


OUTPUT
======


If only :option:`--kill` then there is no output.  If only :option:`--print` then a
timestamped KILL statement if printed for every query that would have been killed, like:


.. code-block:: perl

   # 2009-07-15T15:04:01 KILL 8 (Query 42 sec) SELECT * FROM huge_table


The line shows a timestamp, the query's Id (8), its Time (42 sec) and its
Info (usually the query SQL).

If both :option:`--kill` and :option:`--print` are given, then matching queries are
killed and a line for each like the one above is printed.

Any command executed by :option:`--execute-command` is responsible for its own
output and logging.  After being executed, :program:`pt-kill` has no control or interaction with the command.


OPTIONS
=======

Specify at least one of :option:`--kill`, :option:`--kill-query`, :option:`--print`, :option:`--execute-command` or :option:`--stop`.

:option:`--any-busy-time` and :option:`--each-busy-time` are mutually exclusive.

:option:`--kill` and :option:`--kill-query` are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


.. option:: --ask-pass
 
 Prompt for a password when connecting to |MySQL|.
 

.. option:: --charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets *Perl* 's binmode on
 ``STDOUT`` to utf8, passes the mysql_enable_utf8 option to ``DBD::mysql``, and runs SET
 NAMES UTF8 after connecting to |MySQL|.  Any other value sets binmode on ``STDOUT``
 without the utf8 layer, and runs SET NAMES after connecting to |MySQL|.
 

.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 

.. option:: --daemonize
 
 Fork to the background and detach from the shell.  POSIX operating systems
 only.
 

.. option:: --defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 
.. option:: --group-by
 
 type: string
 
 Apply matches to each class of queries grouped by this SHOW PROCESSLIST column.
 In addition to the basic columns of SHOW PROCESSLIST (user, host, command,
 state, etc.), queries can be matched by \ ``fingerprint``\  which abstracts the
 SQL query in the \ ``Info``\  column.
 
 By default, queries are not grouped, so matches and actions apply to all
 queries.  Grouping allows matches and actions to apply to classes of
 similar queries, if any queries in the class match.
 
 For example, detecting cache stampedes (see \ ``all-but-oldest``\  under
 :option:`--victims` for an explanation of that term) requires that queries are
 grouped by the \ ``arg``\  attribute.  This creates classes of identical queries
 (stripped of comments).  So queries \ ``"SELECT c FROM t WHERE id=1"``\  and
 \ ``"SELECT c FROM t WHERE id=1"``\  are grouped into the same class, but
 query c<"SELECT c FROM t WHERE id=3"> is not identical to the first two
 queries so it is grouped into another class. Then when :option:`--victims`
 \ ``all-but-oldest``\  is specified, all but the oldest query in each class is
 killed for each class of queries that matches the match criteria.
 

.. option:: --help
 
 Show help and exit.
 

.. option:: --host
 
 short form: -h; type: string; default: localhost
 
 Connect to host.
 

.. option:: --interval
 
 type: time
 
 How often to check for queries to kill.  If :option:`--busy-time` is not given,
 then the default interval is 30 seconds.  Else the default is half as often
 as :option:`--busy-time".  If both "--interval" and "--busy-time` are given,
 then the explicit :option:`--interval` value is used.
 
 See also :option:`--run-time`.
 

.. option:: --log
 
 type: string
 
 Print all output to this file when daemonized.
 

.. option:: --password
 
 short form: -p; type: string
 
 Password to use when connecting.
 

.. option:: --pid
 
 type: string
 
 Create the given PID file when daemonized.  The file contains the process ID of
 the daemonized instance.  The PID file is removed when the daemonized instance
 exits.  The program checks for the existence of the PID file when starting; if
 it exists and the process with the matching PID exists, the program exits.
 

.. option:: --port
 
 short form: -P; type: int
 
 Port number to use for connection.
 

.. option:: --run-time
 
 type: time
 
 How long to run before exiting.  By default :program:`pt-kill` runs forever, or until
 its process is killed or stopped by the creation of a :option:`--sentinel` file.
 If this option is specified, :program:`pt-kill` runs for the specified amount of time
 and sleeps :option:`--interval` seconds between each check of the PROCESSLIST.
 

.. option:: --sentinel
 
 type: string; default: /tmp/pt-kill-sentinel
 
 Exit if this file exists.
 
 The presence of the file specified by :option:`--sentinel` will cause all
 running instances of :program:`pt-kill` to exit.  You might find this handy to stop cron
 jobs gracefully if necessary.  See also :option:`--stop`.
 

.. option:: --set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these |MySQL| variables.  Immediately after connecting to |MySQL|, this string
 will be appended to SET and executed.
 

.. option:: --socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 

.. option:: --stop
 
 Stop running instances by creating the :option:`--sentinel` file.
 
 Causes :program:`pt-kill` to create the sentinel file specified by :option:`--sentinel` and
 exit.  This should have the effect of stopping all running instances which are
 watching the same sentinel file.
 

.. option:: --[no]strip-comments
 
 default: yes
 
 Remove SQL comments from queries in the Info column of the PROCESSLIST.
 

.. option:: --user
 
 short form: -u; type: string
 
 User for login if not current user.
 

.. option:: --version
 
 Show version and exit.
 

.. option:: --victims
 
 type: string; default: oldest
 
 Which of the matching queries in each class will be killed.  After classes
 have been matched/filtered, this option specifies which of the matching
 queries in each class will be killed (or printed, etc.).  The following
 values are possible:
 
 oldest
  
  Only kill the single oldest query.  This is to prevent killing queries that
  aren't really long-running, they're just long-waiting.  This sorts matching
  queries by Time and kills the one with the highest Time value.
  
 
 all
  
  Kill all queries in the class.
  
 
 all-but-oldest
  
  Kill all but the oldest query.  This is the inverse of the \ ``oldest``\  value.
  
  This value can be used to prevent "cache stampedes", the condition where
  several identical queries are executed and create a backlog while the first
  query attempts to finish.  Since all queries are identical, all but the first
  query are killed so that it can complete and populate the cache.
  
 

.. option:: --wait-after-kill
 
 type: time
 
 Wait after killing a query, before looking for more to kill.  The purpose of
 this is to give blocked queries a chance to execute, so we don't kill a query
 that's blocking a bunch of others, and then kill the others immediately
 afterwards.
 

.. option:: --wait-before-kill
 
 type: time
 
 Wait before killing a query.  The purpose of this is to give
 :option:`--execute-command` a chance to see the matching query and gather other
 |MySQL| or system information before it's killed.
 


QUERY MATCHES
-------------


These options filter queries from their classes.  If a query does not
match, it is removed from its class.  The \ ``--ignore``\  options take precedence.
The matches for command, db, host, etc. correspond to the columns returned
by SHOW PROCESSLIST: Command, db, Host, etc.  All pattern matches are
case-sensitive by default, but they can be made case-insensitive by specifying
a regex pattern like \ ``(?i-xsm:select)``\ .

See also "GROUP, MATCH AND KILL".


.. option:: --busy-time
 
 type: time; group: Query Matches
 
 Match queries that have been running for longer than this time.  The queries
 must be in Command=Query status.  This matches a query's Time value as
 reported by SHOW PROCESSLIST.
 


.. option:: --idle-time
 
 type: time; group: Query Matches
 
 Match queries that have been idle/sleeping for longer than this time.
 The queries must be in Command=Sleep status.  This matches a query's Time
 value as reported by SHOW PROCESSLIST.
 


.. option:: --ignore-command
 
 type: string; group: Query Matches
 
 Ignore queries whose Command matches this *Perl*  regex.
 
 See :option:`--match-command`.
 


.. option:: --ignore-db
 
 type: string; group: Query Matches
 
 Ignore queries whose db (database) matches this *Perl*  regex.
 
 See :option:`--match-db`.
 


.. option:: --ignore-host
 
 type: string; group: Query Matches
 
 Ignore queries whose Host matches this *Perl*  regex.
 
 See :option:`--match-host`.
 


.. option:: --ignore-info
 
 type: string; group: Query Matches
 
 Ignore queries whose Info (query) matches this *Perl*  regex.
 
 See :option:`--match-info`.
 


.. option:: --[no]ignore-self
 
 default: yes; group: Query Matches
 
 Don't kill :program:`pt-kill`'s own connection.
 


.. option:: --ignore-state
 
 type: string; group: Query Matches; default: Locked
 
 Ignore queries whose State matches this *Perl*  regex.  The default is to keep
 threads from being killed if they are locked waiting for another thread.
 
 See :option:`--match-state`.
 


.. option:: --ignore-user
 
 type: string; group: Query Matches
 
 Ignore queries whose user matches this *Perl*  regex.
 
 See :option:`--match-user`.
 


.. option:: --match-all
 
 group: Query Matches
 
 Match all queries that are not ignored.  If no ignore options are specified,
 then every query matches (except replication threads, unless
 :option:`--replication-threads` is also specified).  This option allows you to
 specify negative matches, i.e. "match every query \ *except*\ ..." where the
 exceptions are defined by specifying various \ ``--ignore``\  options.
 
 This option is \ *not*\  the same as :option:`--victims` \ ``all``\ .  This option matches
 all queries within a class, whereas :option:`--victims` \ ``all``\  specifies that all
 matching queries in a class (however they matched) will be killed.  Normally,
 however, the two are used together because if, for example, you specify
 :option:`--victims` \ ``oldest``\ , then although all queries may match, only the oldest  will be killed.
 

.. option:: --match-command
 
 type: string; group: Query Matches
 
 Match only queries whose Command matches this *Perl*  regex.
 
 Common Command values are:
 
 
 .. code-block:: perl
 
    Query
    Sleep
    Binlog Dump
    Connect
    Delayed insert
    Execute
    Fetch
    Init DB
    Kill
    Prepare
    Processlist
    Quit
    Reset stmt
    Table Dump
 
 
 See `http://dev.mysql.com/doc/refman/5.1/en/thread-commands.html <http://dev.mysql.com/doc/refman/5.1/en/thread-commands.html>`_ for a full
 list and description of Command values.
 

.. option:: --match-db
 
 type: string; group: Query Matches
 
 Match only queries whose db (database) matches this *Perl*  regex.
 

.. option:: --match-host
 
 type: string; group: Query Matches
 
 Match only queries whose Host matches this *Perl*  regex.
 
 The Host value often time includes the port like "host:port".
 

.. option:: --match-info
 
 type: string; group: Query Matches
 
 Match only queries whose Info (query) matches this *Perl*  regex.
 
 The Info column of the processlist shows the query that is being executed
 or NULL if no query is being executed.
 

.. option:: --match-state
 
 type: string; group: Query Matches
 
 Match only queries whose State matches this *Perl*  regex.
 
 Common State values are:
 
 
 .. code-block:: perl
 
    Locked
    login
    copy to tmp table
    Copying to tmp table
    Copying to tmp table on disk
    Creating tmp table
    executing
    Reading from net
    Sending data
    Sorting for order
    Sorting result
    Table lock
    Updating
 
 
 See `http://dev.mysql.com/doc/refman/5.1/en/general-thread-states.html <http://dev.mysql.com/doc/refman/5.1/en/general-thread-states.html>`_ for
 a full list and description of State values.


.. option:: --match-user
 
 type: string; group: Query Matches
 
 Match only queries whose User matches this *Perl*  regex.
 


.. option:: --replication-threads
 
 group: Query Matches
 
 Allow matching and killing replication threads.
 
 By default, matches do not apply to replication threads; i.e. replication
 threads are completely ignored.  Specifying this option allows matches to
 match (and potentially kill) replication threads on masters and slaves.
 


CLASS MATCHES
-------------


These matches apply to entire query classes.  Classes are created by specifying
the :option:`--group-by` option, else all queries are members of a single, default
class.

See also "GROUP, MATCH AND KILL".


.. option:: --any-busy-time
 
 type: time; group: Class Matches
 
 Match query class if any query has been running for longer than this time.
 "Longer than" means that if you specify \ ``10``\ , for example, the class will
 only match if there's at least one query that has been running for greater
 than 10 seconds.
 
 See :option:`--each-busy-time` for more details.
 

.. option:: --each-busy-time
 
 type: time; group: Class Matches
 
 Match query class if each query has been running for longer than this time.
 "Longer than" means that if you specify \ ``10``\ , for example, the class will
 only match if each and every query has been running for greater than 10
 seconds.
 
 See also :option:`--any-busy-time` (to match a class if ANY query has been running
 longer than the specified time) and :option:`--busy-time`.
 

.. option:: --query-count
 
 type: int; group: Class Matches
 
 Match query class if it has at least this many queries.  When queries are
 grouped into classes by specifying :option:`--group-by`, this option causes matches
 to apply only to classes with at least this many queries.  If :option:`--group-by`
 is not specified then this option causes matches to apply only if there
 are at least this many queries in the entire SHOW PROCESSLIST.
 

.. option:: --verbose
 
 short form: -v
 
 Print information to ``STDOUT`` about what is being done.


ACTIONS
-------

These actions are taken for every matching query from all classes.
The actions are taken in this order: :option:`--print`, :option:`--execute-command`,
:option:`--kill` / :option:`--kill-query`.  This order allows :option:`--execute-command` to see the output of :option:`--print` and the query before
:option:`--kill` / :option:`--kill-query`.  This may be helpful because :program:`pt-kill` does not pass any information to :option:`--execute-command`.

See also "GROUP, MATCH AND KILL".

.. option:: --execute-command
 
 type: string; group: Actions
 
 Execute this command when a query matches.
 
 After the command is executed, :program:`pt-kill` has no control over it, so the command
 is responsible for its own info gathering, logging, interval, etc.  The
 command is executed each time a query matches, so be careful that the command
 behaves well when multiple instances are ran.  No information from :program:`pt-kill` is
 passed to the command.
 
 See also :option:`--wait-before-kill`.
 

.. option:: --kill
 
 group: Actions
 
 Kill the connection for matching queries.
 
 This option makes :program:`pt-kill` kill the connections (a.k.a. processes, threads) that
 have matching queries.  Use :option:`--kill-query` if you only want to kill
 individual queries and not their connections.
 
 Unless :option:`--print` is also given, no other information is printed that shows
 that :program:`pt-kill` matched and killed a query.
 
 See also :option:`--wait-before-kill` and :option:`--wait-after-kill`.
 

.. option:: --kill-query
 
 group: Actions
 
 Kill matching queries.
 
 This option makes :program:`pt-kill` kill matching queries.  This requires |MySQL| 5.0 or newer.  Unlike :option:`--kill` which kills the connection for matching queries,
 this option only kills the query, not its connection.
 
.. option:: --print
 
 group: Actions
 
 Print a KILL statement for matching queries; does not actually kill queries.
 
 If you just want to see which queries match and would be killed without
 actually killing them, specify :option:`--print`.  To both kill and print
 matching queries, specify both :option:`--kill` and :option:`--print`.
 

DSN OPTIONS
===========


These DSN options are used to create a DSN.  Each option is given like
\ ``option=value``\ .  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the \ ``=``\  and
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

    PTDEBUG=1 pt-kill ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-kill <http://www.percona.com/bugs/pt-kill>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.


AUTHORS
=======

*Baron Schwartz* and *Daniel Nichter*

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2009-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

:program:`pt-kill` 1.0.1

