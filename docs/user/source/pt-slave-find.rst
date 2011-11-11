.. program:: pt-slave-find

==========================
 :program:`pt-slave-find`
==========================

.. highlight:: perl


NAME
====

 :program:`pt-slave-find` - Find and print replication hierarchy tree of |MySQL| slaves.


SYNOPSIS
========


Usage
-----

::

   pt-slave-find [OPTION...] MASTER-HOST

:program:`pt-slave-find` finds and prints a hierarchy tree of |MySQL| slaves.

Examples
--------

.. code-block:: perl

    pt-slave-find --host master-host



RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-slave-find` is read-only and very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-slave-find <http://www.percona.com/bugs/pt-slave-find>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-slave-find` connects to a |MySQL| replication master and finds its slaves.
Currently the only thing it can do is print a tree-like view of the replication
hierarchy.

The master host can be specified using one of two methods.  The first method is
to use the standard connection-related command line options:
:option:`--defaults-file`, :option:`--password`, :option:`--host`, :option:`--port`, :option:`--socket` or :option:`--user`.

The second method to specify the master host is a DSN.  A DSN is a special
syntax that can be either just a hostname (like \ ``server.domain.com``\  or
\ ``1.2.3.4``\ ), or a \ ``key=value,key=value``\  string. Keys are a single letter:


.. code-block:: perl

    KEY MEANING
    === =======
    h   Connect to host
    P   Port number to use for connection
    S   Socket file to use for connection
    u   User for login if not current user
    p   Password to use when connecting
    F   Only read default options from the given file


:program:`pt-slave-find` reads all normal |MySQL| option files, such as :option:`~/.my.cnf`, so you may not need to specify username, password and other common options at all.


EXIT STATUS
===========


An exit status of 0 (sometimes also called a return value or return code)
indicates success.  Any other value represents the exit status of
the *Perl*  process itself.


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
 
 type: string; short form: -D
 
 Database to use.
 


.. option:: --defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


.. option:: --help
 
 Show help and exit.
 


.. option:: --host
 
 short form: -h; type: string
 
 Connect to host.
 


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
 


.. option:: --recurse
 
 type: int
 
 Number of levels to recurse in the hierarchy.  Default is infinite.
 
 See :option:`--recursion-method`.
 


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
 port (not 3306).  Usually :program:`pt-slave-find` does the right thing and finds
 the slaves, but you may give a preferred method and it will be used first.
 If it doesn't find any slaves, the other methods will be tried.
 


.. option:: --report-format
 
 type: string; default: summary
 
 Set what information about the slaves is printed.  The report format can be
 one of the following:
 
 
   * ``hostname``
  
  Print just the hostname name of the slaves.  It looks like:
  
  
  .. code-block:: perl
  
     127.0.0.1:12345
     +- 127.0.0.1:12346
        +- 127.0.0.1:12347
  
  
 
 
  * ``summary``
  
  Print a summary of each slave's settings.  This report shows more information
  about each slave, like:
  
  
  .. code-block:: perl
  
     127.0.0.1:12345
     Version         5.1.34-log
     Server ID       12345
     Uptime          04:56 (started 2010-06-17T11:21:22)
     Replication     Is not a slave, has 1 slaves connected
     Filters         
     Binary logging  STATEMENT
     Slave status    
     Slave mode      STRICT
     Auto-increment  increment 1, offset 1
     +- 127.0.0.1:12346
        Version         5.1.34-log
        Server ID       12346
        Uptime          04:54 (started 2010-06-17T11:21:24)
        Replication     Is a slave, has 1 slaves connected
        Filters         
        Binary logging  STATEMENT
        Slave status    0 seconds behind, running, no errors
        Slave mode      STRICT
        Auto-increment  increment 1, offset 1
  
  
 
 


.. option:: --set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these |MySQL| variables.  Immediately after connecting to |MySQL|, this
 string will be appended to SET and executed.
 


.. option:: --socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


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

    PTDEBUG=1 :program:`pt-slave-find` ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-slave-find <http://www.percona.com/bugs/pt-slave-find>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.


AUTHORS
=======


*Baron Schwartz* and *Daniel Nichter*


COPYRIGHT, LICENSE, AND WARRANTY
================================


This program is copyright 2007-2011 *Baron Schwartz*, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

:program:`pt-slave-find` 1.0.1

