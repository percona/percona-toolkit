.. program:: pt-show-grants

===========================
 :program:`pt-show-grants`
===========================

.. highlight:: perl


NAME
====

 :program:`pt-show-grants` - Canonicalize and print |MySQL| grants so you can effectively replicate, compare and version-control them.


SYNOPSIS
========


Usage
-----

::

   pt-show-grants [OPTION...] [DSN]

:program:`pt-show-grants` shows grants (user privileges) from a |MySQL| server.

Examples
--------

.. code-block:: perl

    pt-show-grants
 
    pt-show-grants --separate --revoke | diff othergrants.sql -



RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-show-grants` is read-only by default, and very low-risk.  If you specify
:option:`--flush`, it will execute \ ``FLUSH PRIVILEGES``\ .

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-show-grants <http://www.percona.com/bugs/pt-show-grants>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-show-grants` extracts, orders, and then prints grants for |MySQL| user
accounts.

Why would you want this?  There are several reasons.

The first is to easily replicate users from one server to another; you can
simply extract the grants from the first server and pipe the output directly
into another server.

The second use is to place your grants into version control.  If you do a daily
automated grant dump into version control, you'll get lots of spurious
changesets for grants that don't change, because |MySQL| prints the actual grants
out in a seemingly random order.  For instance, one day it'll say


.. code-block:: perl

   GRANT DELETE, INSERT, UPDATE ON `test`.* TO 'foo'@'%';


And then another day it'll say


.. code-block:: perl

   GRANT INSERT, DELETE, UPDATE ON `test`.* TO 'foo'@'%';


The grants haven't changed, but the order has.  This script sorts the grants
within the line, between 'GRANT' and 'ON'.  If there are multiple rows from SHOW
GRANTS, it sorts the rows too, except that it always prints the row with the
user's password first, if it exists.  This removes three kinds of inconsistency
you'll get from running SHOW GRANTS, and avoids spurious changesets in version
control.

Third, if you want to diff grants across servers, it will be hard without
"canonicalizing" them, which :program:`pt-show-grants` does.  The output is fully
diff-able.

With the :option:`--revoke`, :option:`--separate` and other options, :program:`pt-show-grants` also makes it easy to revoke specific privileges from users.  This is tedious
otherwise.


OPTIONS
=======


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


.. option:: --ask-pass
 
 Prompt for a password when connecting to |MySQL|.
 


.. option:: --charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets *Perl* 's binmode on
 ``STDOUT`` to utf8, passes the mysql_enable_utf8 option to ``DBD::mysql``, and
 runs SET NAMES UTF8 after connecting to |MySQL|.  Any other value sets
 binmode on ``STDOUT`` without the utf8 layer, and runs SET NAMES after
 connecting to |MySQL|.
 


.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


.. option:: --database
 
 short form: -D; type: string
 
 The database to use for the connection.
 


.. option:: --defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


.. option:: --drop
 
 Add DROP USER before each user in the output.
 


.. option:: --flush
 
 Add FLUSH PRIVILEGES after output.
 
 You might need this on pre-4.1.1 servers if you want to drop a user completely.
 


.. option:: --[no]header
 
 default: yes
 
 Print dump header.
 
 The header precedes the dumped grants.  It looks like:
 
 
 .. code-block:: perl
 
    -- Grants dumped by :program:`pt-show-grants` 1.0.19
    -- Dumped from server Localhost via UNIX socket, |MySQL| 5.0.82-log at 2009-10-26 10:01:04
 
 
 See also :option:`--[no]timestamp`.
 


.. option:: --help
 
 Show help and exit.
 


.. option:: --host
 
 short form: -h; type: string
 
 Connect to host.
 


.. option:: --ignore
 
 type: array
 
 Ignore this comma-separated list of users.
 


.. option:: --only
 
 type: array
 
 Only show grants for this comma-separated list of users.
 


.. option:: --password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


.. option:: --pid
 
 type: string
 
 Create the given PID file.  The file contains the process ID of the script.
 The PID file is removed when the script exits.  Before starting, the script
 checks if the PID file already exists.  If it does not, then the script creates
 and writes its own PID to it.  If it does, then the script checks the following:
 if the file contains a PID and a process is running with that PID, then
 the script dies; or, if there is no process running with that PID, then the
 script overwrites the file with its own PID and starts; else, if the file
 contains no PID, then the script dies.
 


.. option:: --port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


.. option:: --revoke
 
 Add REVOKE statements for each GRANT statement.
 


.. option:: --separate
 
 List each GRANT or REVOKE separately.
 
 The default output from |MySQL|'s SHOW GRANTS command lists many privileges on a
 single line.  With :option:`--flush`, places a FLUSH PRIVILEGES after each user,
 instead of once at the end of all the output.
 


.. option:: --set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these |MySQL| variables.  Immediately after connecting to |MySQL|, this
 string will be appended to SET and executed.
 


.. option:: --socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


.. option:: --[no]timestamp
 
 default: yes
 
 Add timestamp to the dump header.
 
 See also :option:`--[no]header`.
 


.. option:: --user
 
 short form: -u; type: string
 
 User for login if not current user.
 


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

    PTDEBUG=1 :program:`pt-show-grants` ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-show-grants <http://www.percona.com/bugs/pt-show-grants>`_.

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

:program:`pt-show-grants` 1.0.1

