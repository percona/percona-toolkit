
#######
pt-mext
#######

.. highlight:: perl


****
NAME
****


pt-mext - Look at many samples of MySQL \ ``SHOW GLOBAL STATUS``\  side-by-side.


********
SYNOPSIS
********


Usage: pt-mext [OPTIONS] -- COMMAND

pt-mext columnizes repeated output from a program like mysqladmin extended.

Get output from \ ``mysqladmin``\ :


.. code-block:: perl

    pt-mext -r -- mysqladmin ext -i10 -c3"


Get output from a file:


.. code-block:: perl

    pt-mext -r -- cat mysqladmin-output.txt



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-mext is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-mext <http://www.percona.com/bugs/pt-mext>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-mext executes the \ ``COMMAND``\  you specify, and reads through the result one
line at a time.  It places each line into a temporary file.  When it finds a
blank line, it assumes that a new sample of SHOW GLOBAL STATUS is starting,
and it creates a new temporary file.  At the end of this process, it has a
number of temporary files.  It joins the temporary files together side-by-side
and prints the result.  If the "-r" option is given, it first subtracts
each sample from the one after it before printing results.


*******
OPTIONS
*******



-r
 
 Relative: subtract each column from the previous column.
 



***********
ENVIRONMENT
***********


This tool does not use any environment variables.


*******************
SYSTEM REQUIREMENTS
*******************


This tool requires the Bourne shell (\ */bin/sh*\ ) and the seq program.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-mext <http://www.percona.com/bugs/pt-mext>`_.

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


This program is copyright 2010 Baron Schwartz, 2011 Percona Inc.
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

