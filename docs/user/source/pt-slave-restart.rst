.. program:: pt-slave-restart

=============================
 :program:`pt-slave-restart`
=============================

.. highlight:: perl


NAME
====

 :program:`pt-slave-restart` - Watch and restart |MySQL| replication after errors.


SYNOPSIS
========


Usage
-----

::

   pt-slave-restart [OPTION...] [DSN]

:program:`pt-slave-restart` watches one or more |MySQL| replication slaves for
errors, and tries to restart replication if it stops.


RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-slave-restart` is a brute-force way to try to keep a slave server running when
it is having problems with replication.  Don't be too hasty to use it unless you
need to.  If you use this tool carelessly, you might miss the chance to really
solve the slave server's problems.

At the time of this release there is a bug that causes an invalid
\ ``CHANGE MASTER TO``\  statement to be executed.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-slave-restart <http://www.percona.com/bugs/pt-slave-restart>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-slave-restart` watches one or more |MySQL| replication slaves and tries to skip statements that cause errors.  It polls slaves intelligently with an
exponentially varying sleep time.  You can specify errors to skip and run the
slaves until a certain binlog position.

Note: it has come to my attention that Yahoo! had or has an internal tool
called fix_repl, described to me by a past Yahoo! employee and mentioned in
the first edition of *High Performance MySQL*.  Apparently this tool does the
same thing.  Make no mistake, though: this is not a way to "fix replication."
In fact I would not even encourage its use on a regular basis; I use it only
when I have an error I know I just need to skip past.


OUTPUT
======


If you specify :option:`--verbose`, :program:`pt-slave-restart` prints a line every time it sees
the slave has an error.  See :option:`--verbose` for details.


SLEEP
=====

 :program:`pt-slave-restart` sleeps intelligently between polling the slave.  The current
sleep time varies.


  *  The initial sleep time is given by :option:`--sleep`.

  * If it checks and finds an error, it halves the previous sleep time.

  * If it finds no error, it doubles the previous sleep time.
 
  * The sleep time is bounded below by :option:`--min-sleep` and above by
 :option:`--max-sleep`.

  * Immediately after finding an error, :program:`pt-slave-restart` assumes another error is very likely to happen next, so it sleeps the current sleep time or the initial
 sleep time, whichever is less.
 

EXIT STATUS
===========


An exit status of 0 (sometimes also called a return value or return code)
indicates success.  Any other value represents the exit status of the *Perl* 
process itself, or of the last forked process that exited if there were multiple
servers to monitor.


COMPATIBILITY
=============

:program:`pt-slave-restart` should work on many versions of |MySQL|.  Lettercase of many output columns from SHOW SLAVE STATUS has changed over time, so it treats them
all as lowercase.


OPTIONS
=======


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


.. option:: --always
 
 Start slaves even when there is no error.  With this option enabled,
 :program:`pt-slave-restart` will not let you stop the slave manually if you want to!
 


.. option:: --ask-pass
 
 Prompt for a password when connecting to |MySQL|.
 


.. option:: --charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets *Perl* 's binmode on
 ``STDOUT`` to utf8, passes the mysql_enable_utf8 option to ``DBD::mysql``, and
 runs SET NAMES UTF8 after connecting to |MySQL|.  Any other value sets
 binmode on ``STDOUT`` without the utf8 layer, and runs SET NAMES after
 connecting to |MySQL|.
 


.. option:: --[no]check-relay-log
 
 default: yes
 
 Check the last relay log file and position before checking for slave errors.
 
 By default :program:`pt-slave-restart` will not doing anything (it will just sleep)
 if neither the relay log file nor the relay log position have changed since
 the last check.  This prevents infinite loops (i.e. restarting the same
 error in the same relay log file at the same relay log position).
 
 For certain slave errors, however, this check needs to be disabled by
 specifying :option:`--no-check-relay-log`.  Do not do this unless you know what
 you are doing!
 


.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


.. option:: --daemonize
 
 Fork to the background and detach from the shell.  POSIX
 operating systems only.
 


.. option:: --database
 
 short form: -D; type: string
 
 Database to use.
 


.. option:: --defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


.. option:: --error-length
 
 type: int
 
 Max length of error message to print.  When :option:`--verbose` is set high enough to
 print the error, this option will truncate the error text to the specified
 length.  This can be useful to prevent wrapping on the terminal.
 


.. option:: --error-numbers
 
 type: hash
 
 Only restart this comma-separated list of errors.  Makes :program:`pt-slave-restart` only  try to restart if the error number is in this comma-separated list of errors.
 If it sees an error not in the list, it will exit.
 
 The error number is in the \ ``last_errno``\  column of \ ``SHOW SLAVE STATUS``\ .
 


.. option:: --error-text
 
 type: string
 
 Only restart errors that match this pattern.  A *Perl*  regular expression against
 which the error text, if any, is matched.  If the error text exists and matches,
 :program:`pt-slave-restart` will try to restart the slave.  If it exists but doesn't match, :program:`pt-slave-restart` will exit.
 
 The error text is in the \ ``last_error``\  column of \ ``SHOW SLAVE STATUS``\ .
 

.. option:: --help
 
 Show help and exit.
 

.. option:: --host
 
 short form: -h; type: string
 
 Connect to host.
 

.. option:: --log
 
 type: string
 
 Print all output to this file when daemonized.
 

.. option:: --max-sleep
 
 type: float; default: 64
 
 Maximum sleep seconds.
 
 The maximum time :program:`pt-slave-restart` will sleep before polling the slave again.
 This is also the time that :program:`pt-slave-restart` will wait for all other running
 instances to quit if both :option:`--stop` and :option:`--monitor` are specified.
 
 See "SLEEP".
 

.. option:: --min-sleep
 
 type: float; default: 0.015625
 
 The minimum time :program:`pt-slave-restart` will sleep before polling the slave again.
 See "SLEEP".
 

.. option:: --monitor
 
 Whether to monitor the slave (default).  Unless you specify :option:`--monitor`
 explicitly, :option:`--stop` will disable it.
 


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
 


.. option:: --quiet
 
 short form: -q
 
 Suppresses normal output (disables :option:`--verbose`).
 


.. option:: --recurse
 
 type: int; default: 0
 
 Watch slaves of the specified server, up to the specified number of servers deep
 in the hierarchy.  The default depth of 0 means "just watch the slave
 specified."
 
 :program:`pt-slave-restart` examines \ ``SHOW PROCESSLIST``\  and tries to determine which  connections are from slaves, then connect to them.  See :option:`--recursion-method`.
 
 Recursion works by finding all slaves when the program starts, then watching
 them.  If there is more than one slave, :program:`pt-slave-restart` uses \ ``fork()``\  to  monitor them.
 
 This also works if you have configured your slaves to show up in \ ``SHOW SLAVE
 HOSTS``\ .  The minimal configuration for this is the \ ``report_host``\  parameter, but there are other "report" parameters as well for the port, username, and
 password.
 


.. option:: --recursion-method
 
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
 port (not 3306).  Usually :program:`pt-slave-restart` does the right thing and finds
 the slaves, but you may give a preferred method and it will be used first.
 If it doesn't find any slaves, the other methods will be tried.
 

.. option:: --run-time
 
 type: time
 
 Time to run before exiting.  Causes :program:`pt-slave-restart` to stop after the specified  time has elapsed.  Optional suffix: s=seconds, m=minutes, h=hours, d=days; if no suffix, s is used.
 
.. option:: --sentinel
 
 type: string; default: /tmp/pt-slave-restart-sentinel
 
 Exit if this file exists.
 


.. option:: --set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these |MySQL| variables.  Immediately after connecting to |MySQL|, this string
 will be appended to SET and executed.
 


.. option:: --skip-count
 
 type: int; default: 1
 
 Number of statements to skip when restarting the slave.
 


.. option:: --sleep
 
 type: int; default: 1
 
 Initial sleep seconds between checking the slave.
 
 See "SLEEP".
 


.. option:: --socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


.. option:: --stop
 
 Stop running instances by creating the sentinel file.
 
 Causes :program:`pt-slave-restart` to create the sentinel file specified by
 :option:`--sentinel`.  This should have the effect of stopping all running
 instances which are watching the same sentinel file.  If :option:`--monitor` isn't
 specified, :program:`pt-slave-restart` will exit after creating the file.  If it is
 specified, :program:`pt-slave-restart`  will wait the interval given by
 :option:`--max-sleep`, then remove the file and continue working.
 
 You might find this handy to stop cron jobs gracefully if necessary, or to
 replace one running instance with another.  For example, if you want to stop
 and restart :program:`pt-slave-restart` every hour (just to make sure that it is
 restarted every hour, in case of a server crash or some other problem), you
 could use a ``crontab`` line like this:
 
 
 .. code-block:: perl
 
   0 * * * * pt-slave-restart --monitor --stop --sentinel /tmp/pt-slave-restartup
 
 
 The non-default :option:`--sentinel` will make sure the hourly \ ``cron``\  job stops
 only instances previously started with the same options (that is, from the
 same \ ``cron``\  job).
 
 See also :option:`--sentinel`.
 

.. option:: --until-master
 
 type: string
 
 Run until this master log file and position.  Start the slave, and retry if it
 fails, until it reaches the given replication coordinates.  The coordinates are
 the logfile and position on the master, given by relay_master_log_file,
 exec_master_log_pos.  The argument must be in the format "file,pos".  Separate
 the filename and position with a single comma and no space.
 
 This will also cause an UNTIL clause to be given to START SLAVE.
 
 After reaching this point, the slave should be stopped and :program:`pt-slave-restart`
 will exit.
 


.. option:: --until-relay
 
 type: string
 
 Run until this relay log file and position.  Like :option:`--until-master`, but in
 the slave's relay logs instead.  The coordinates are given by relay_log_file,
 relay_log_pos.
 


.. option:: --user
 
 short form: -u; type: string
 
 User for login if not current user.
 


.. option:: --verbose
 
 short form: -v; cumulative: yes; default: 1
 
 Be verbose; can specify multiple times.  Verbosity 1 outputs connection
 information, a timestamp, relay_log_file, relay_log_pos, and last_errno.
 Verbosity 2 adds last_error.  See also :option:`--error-length`.  Verbosity 3 prints
 the current sleep time each time :program:`pt-slave-restart` sleeps.
 


.. option:: --version



Show version and exit.


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

    PTDEBUG=1 pt-slave-restart ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-slave-restart <http://www.percona.com/bugs/pt-slave-restart>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======

*Baron Schwartz*


COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2007-2011 *Baron Schwartz*, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

 :program:`pt-slave-restart` 1.0.1

