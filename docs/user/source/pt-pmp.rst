.. program:: pt-pmp

===================
 :program:`pt-pmp`
===================

.. highlight:: perl


NAME
====

 :program:`pt-pmp` - Aggregate GDB stack traces for a selected program.


SYNOPSIS
========


Usage
-----

::

   pt-pmp [OPTIONS] [FILES]

:program:`pt-pmp` is a poor man's profiler, inspired by `http://poormansprofiler.org <http://poormansprofiler.org>`_.

It can create and summarize full stack traces of processes on Linux.
Summaries of stack traces can be an invaluable tool for diagnosing what
a process is waiting for.


RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-pmp` is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-pmp <http://www.percona.com/bugs/pt-pmp>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-pmp` performs two tasks: it gets a stack trace, and it summarizes the stack
trace.  If a file is given on the command line, the tool skips the first step and just aggregates the file.

To summarize the stack trace, the tool extracts the function name (symbol)
from each level of the stack, and combines them with commas.  It does this
for each thread in the output.  Afterwards, it sorts similar threads together
and counts how many of each one there are, then sorts them most-frequent first.


OPTIONS
=======


Options must precede files on the command line.


.. option:: -b BINARY
 
 Which binary to trace (default mysqld)
 


.. option:: -i ITERATIONS
 
 How many traces to gather and aggregate (default 1)
 


.. option:: -k KEEPFILE
 
 Keep the raw traces in this file after aggregation
 


.. option:: -l NUMBER
 
 Aggregate only first NUMBER functions; 0=infinity (default 0)
 


.. option:: -p PID
 
 Process ID of the process to trace; overrides -b
 


.. option:: -s SLEEPTIME
 
 Number of seconds to sleep between iterations (default 0)
 



ENVIRONMENT
===========


This tool does not use any environment variables.


SYSTEM REQUIREMENTS
===================


This tool requires Bash v3 or newer.


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-pmp <http://www.percona.com/bugs/pt-pmp>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.


AUTHORS
=======


*Baron Schwartz*, based on a script by *Domas Mituzas* (`http://poormansprofiler.org/ <http://poormansprofiler.org/>`_)


COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2010-2011 *Baron Schwartz*, 2011 Percona Inc.
Feedback and improvements are welcome.


VERSION
=======

:program:`pt-pmp` 1.0.1

