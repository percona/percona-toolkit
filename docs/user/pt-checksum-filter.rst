
##################
pt-checksum-filter
##################

.. highlight:: perl


****
NAME
****


pt-checksum-filter - Filter checksums from pt-table-checksum.


********
SYNOPSIS
********


Usage: pt-checksum-filter [OPTION]... FILE

pt-checksum-filter filters checksums from pt-table-checksum and prints those
that differ.  With no FILE, or when FILE is -, read standard input.

Examples:


.. code-block:: perl

   pt-checksum-filter checksums.txt
 
   pt-table-checksum host1 host2 | pt-checksum-filter
 
   pt-checksum-filter db1-checksums.txt db2-checksums.txt --ignore-databases



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-checksum-filter is read-only and very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-checksum-filter <http://www.percona.com/bugs/pt-checksum-filter>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


This program takes the unsorted, verbose output from pt-table-checksum and
sorts it, then filters it so you only see lines that have different checksums
or counts.

You can pipe input directly into it from pt-table-checksum, or you can
save the pt-table-checksum's output and run pt-checksum-filter on the
resulting file(s).  If you run it against just one file, or pipe output
directly into it, it'll output results during processing.  Processing multiple
files is slightly more expensive, and you won't see any output until they're
all read.


***********
EXIT STATUS
***********


An exit status of 0 (sometimes also called a return value or return code)
indicates that no differences were found.  If there were any differences, the
tool exits with status 1.


*******
OPTIONS
*******


"--ignore-databases" and "--equal-databases" are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--equal-databases
 
 type: Hash
 
 This comma-separated list of databases are equal.
 
 These database names are always considered to have the same tables.  In other
 words, this makes \ ``database1.table1.chunk1``\  equal to \ ``database2.table1.chunk1``\ 
 if they have the same checksum.
 
 This disables incremental processing, so you won't see any results until all
 input is processed.
 


--header
 
 short form: -h
 
 Preserves headers output by pt-table-checksum.
 


--help
 
 Show help and exit.
 


--ignore-databases
 
 Ignore the database name when comparing lines.
 
 This disables incremental processing, so you won't see any results until all
 input is processed.
 


--master
 
 type: string
 
 The name of the master server.
 
 Specifies which host is the replication master, and sorts lines for that host
 first, so you can see the checksum values on the master server before the
 slave.
 


--unique
 
 type: string
 
 Show unique differing host/db/table names.
 
 The argument must be one of host, db, or table.
 


--verbose
 
 short form: -v
 
 Output all lines, even those that have no differences, except for header lines.
 


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

    PTDEBUG=1 pt-checksum-filter ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-checksum-filter <http://www.percona.com/bugs/pt-checksum-filter>`_.

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

