
##################
pt-profile-compact
##################

.. highlight:: perl


****
NAME
****


pt-profile-compact - Compact the output from pt-query-profiler.


********
SYNOPSIS
********


Usage: pt-profile-compact [OPTION...] [FILE...]

pt-profile-compact aligns query profiler results side by side for easy
comparison.  With no FILE, or when FILE is -, read from standard input.

To view queries 2, 4 and 6 side by side:


.. code-block:: perl

    pt-profile-compact --queries 2,4,6 profile-results.txt


To view summaries from two runs side by side:


.. code-block:: perl

    pt-profile-compact --mode SUMMARY results-1.txt results-2.txt



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-profile-compact is read-only and very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-profile-compact <http://www.percona.com/bugs/pt-profile-compact>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-profile-compact slices and aligns the output from pt-query-profiler
so you can compare profile results side by side easily.  It prints the first
profile result intact, but each subsequent result is trimmed to be as narrow
as possible, then aligned next to the first.

You can also use this to examine only some profile results.  For example, if
you have a set of queries to get a table into a known state, and then a query
you want to profile, you can ignore the setup queries.  This is typically easy
to do with a command-line option like "--queries" 4,8,12,16,20 to view
every 4th query.

If the first profile it sees is labeled QUERY X, it will only look at QUERY
profiles from then on.  The same holds for SUMMARY profiles.  This is because
there are different numbers of lines in QUERY and SUMMARY profiles.  You can
specify which kind of profile result you want to process.  See
pt-query-profiler for the full list of types.


*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--headers
 
 type: int; default: 2000
 
 Reprint headers every N queries.
 


--help
 
 Show help and exit.
 


--mode
 
 type: string
 
 What type of reports (EXTERNAL, QUERY, SUMMARY) to process.
 


--queries
 
 type: hash
 
 Process only this comma-separated list of queries.
 


--version
 
 Show version and exit.
 



***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-profile-compact ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-profile-compact <http://www.percona.com/bugs/pt-profile-compact>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.
Include the following information in your bug report:


\* Complete command-line used to run the tool



\* Tool "--version"



\* MySQL version of all servers involved



\* Output from the tool including STDERR



\* Input files (log/dump/config files, etc.)



If possible, include debugging output by running the tool with \ ``PTDEBUG``\ ;
see "ENVIRONMENT".


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


Percona Toolkit v0.9.5 released 2011-08-04

