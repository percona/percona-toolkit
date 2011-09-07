.. program:: pt-fifo-split

==========================
 :program:`pt-fifo-split`
==========================

.. highlight:: perl


NAME
====

:program:`pt-fifo-split` - Split files and pipe lines to a fifo without really splitting.


SYNOPSIS
========

Usage
-----

:: 

  pt-fifo-split [options] [FILE ...]

:program:`pt-fifo-split` splits FILE and pipes lines to a fifo.  With no FILE, or when FILE is -, read standard input.

Read hugefile.txt in chunks of a million lines without physically splitting it:

.. code-block:: perl

  pt-fifo-split --lines 1000000 hugefile.txt
  while [ -e /tmp/pt-fifo-split ]; do cat /tmp/pt-fifo-split; done

RISKS
=====

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-fifo-split` creates and/or deletes the "--fifo" file.  Otherwise, no other files are modified, and it merely reads lines from the file given on the command-line.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-fifo-split <http://www.percona.com/bugs/pt-fifo-split>`_.

See also "BUGS" for more information on filing bugs and getting help.

DESCRIPTION
===========

:program:`pt-fifo-split` lets you read from a file as though it contains only some of the lines in the file.  When you read from it again, it contains the next set of lines; when you have gone all the way through it, the file disappears.  This works only on Unix-like operating systems.

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
 
.. option:: --fifo
 
 type: string; default: /tmp/pt-fifo-split
 
 The name of the fifo from which the lines can be read.
 
.. option:: --force
 
 Remove the fifo if it exists already, then create it again.
 
.. option:: --help
 
 Show help and exit.
 
.. option:: --lines
 
 type: int; default: 1000
 
 The number of lines to read in each chunk.
 
.. option:: --offset
 
 type: int; default: 0
 
 Begin at the Nth line.  If the argument is 0, all lines are printed to the fifo.
 If 1, then beginning at the first line, lines are printed (exactly the same as
 0).  If 2, the first line is skipped, and the 2nd and subsequent lines are
 printed to the fifo.
 
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
 
.. option:: --statistics
 
 Print out statistics between chunks.  The statistics are the number of chunks,
 the number of lines, elapsed time, and lines per second overall and during the
 last chunk.
 
.. option:: --version
 
 Show version and exit.
 
ENVIRONMENT
===========

The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-fifo-split ... > FILE 2>&1

Be careful: debugging output is voluminous and can generate several megabytes
of output.


SYSTEM REQUIREMENTS
===================

You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.

BUGS
====

For a list of known bugs, see `http://www.percona.com/bugs/pt-fifo-split <http://www.percona.com/bugs/pt-fifo-split>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.

AUTHORS
=======

Baron Schwartz

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

:program:`pt-fifo-split` 1.0.1

