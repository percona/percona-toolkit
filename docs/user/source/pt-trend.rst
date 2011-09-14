.. program:: pt-trend


=====================
 :program:`pt-trend`
=====================

.. highlight:: perl


NAME
====

 :program:`pt-trend` - Compute statistics over a set of time-series data points.


SYNOPSIS
========


Usage
-----

::

   pt-trend [OPTION...] [FILE ...]

:program:`pt-trend` reads a slow query log and outputs statistics on it.


RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-trend` simply reads files give on the command-line.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-trend <http://www.percona.com/bugs/pt-trend>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========


You can specify multiple files on the command line.  If you don't specify any,
or if you use the special filename \ ``-``\ , lines are read from standard input.


OPTIONS
=======


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


.. option:: --config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


.. option:: --help
 
 Show help and exit.
 


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
 


.. option:: --progress
 
 type: array; default: time,15
 
 Print progress reports to ``STDERR``.  The value is a comma-separated list with two
 parts.  The first part can be percentage, time, or iterations; the second part
 specifies how often an update should be printed, in percentage, seconds, or
 number of iterations.
 


.. option:: --version
 
 Show version and exit.
 


ENVIRONMENT
===========


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to ``STDERR``.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 :program:`pt-trend` ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================


You need *Perl* , ``DBI``, ``DBD::mysql``, and some core packages that ought to be
installed in any reasonably new version of *Perl* .


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-trend <http://www.percona.com/bugs/pt-trend>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======


*Baron Schwartz*


COPYRIGHT, LICENSE, AND WARRANTY
================================


This program is copyright 2010-2011 *Baron Schwartz*, 2011 Percona Inc.
Feedback and improvements are welcome.


VERSION
=======

:program:`pt-trend` 1.0.1

