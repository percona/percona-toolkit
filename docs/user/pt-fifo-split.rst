
#############
pt-fifo-split
#############

.. highlight:: perl


****
NAME
****


pt-fifo-split - Split files and pipe lines to a fifo without really splitting.


********
SYNOPSIS
********


Usage: pt-fifo-split [options] [FILE ...]

pt-fifo-split splits FILE and pipes lines to a fifo.  With no FILE, or when FILE
is -, read standard input.

Read hugefile.txt in chunks of a million lines without physically splitting it:


.. code-block:: perl

  pt-fifo-split --lines 1000000 hugefile.txt
  while [ -e /tmp/pt-fifo-split ]; do cat /tmp/pt-fifo-split; done



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-fifo-split creates and/or deletes the "--fifo" file.  Otherwise, no other
files are modified, and it merely reads lines from the file given on the
command-line.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-fifo-split <http://www.percona.com/bugs/pt-fifo-split>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-fifo-split lets you read from a file as though it contains only some of the
lines in the file.  When you read from it again, it contains the next set of
lines; when you have gone all the way through it, the file disappears.  This
works only on Unix-like operating systems.

You can specify multiple files on the command line.  If you don't specify any,
or if you use the special filename \ ``-``\ , lines are read from standard input.


*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--fifo
 
 type: string; default: /tmp/pt-fifo-split
 
 The name of the fifo from which the lines can be read.
 


--force
 
 Remove the fifo if it exists already, then create it again.
 


--help
 
 Show help and exit.
 


--lines
 
 type: int; default: 1000
 
 The number of lines to read in each chunk.
 


--offset
 
 type: int; default: 0
 
 Begin at the Nth line.  If the argument is 0, all lines are printed to the fifo.
 If 1, then beginning at the first line, lines are printed (exactly the same as
 0).  If 2, the first line is skipped, and the 2nd and subsequent lines are
 printed to the fifo.
 


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
 


--statistics
 
 Print out statistics between chunks.  The statistics are the number of chunks,
 the number of lines, elapsed time, and lines per second overall and during the
 last chunk.
 


--version
 
 Show version and exit.
 



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


***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-fifo-split ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-fifo-split <http://www.percona.com/bugs/pt-fifo-split>`_.

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


Baron Schwartz


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

