
##########
pt-collect
##########

.. highlight:: perl


****
NAME
****


pt-collect - Collect information from a server for some period of time.


********
SYNOPSIS
********


Usage: pt-collect -d -g -i -o -s [OPTIONS] [-- MYSQL-OPTIONS]

pt-collect tool gathers a variety of information about a system for a period
of time.  It is typically executed when the stalk tool detects a condition
and wants to collect information to assist in diagnosis.  Four options
must be specified on the command line: -dgios.


*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-collect is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-collect <http://www.percona.com/bugs/pt-collect>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-collect creates a lock to ensure that only one instance runs at a time,
and then saves a variety of performance and status data into files in the
configured directory.  Files are named with a timestamp so they can be
grouped together.  The tool is MySQL-centric by default, and gathers quite
a bit of diagnostic data that's useful for understanding the behavior of
a MySQL database server.

Options after \ ``--``\  are passed to \ ``mysql``\  and \ ``mysqladmin``\ .


*******
OPTIONS
*******



-d (required)
 
 DESTINATION Where to store the resulting data; must already exist.
 


-g <yes/no> (required)
 
 Collect GDB stack traces.
 


-i INTERVAL (required)
 
 How many seconds to collect data.
 


-o <yes/no> (required)
 
 Collect oprofile data; disables -s.
 


-s <yes/no> (required)
 
 Collect strace data.
 


-f PERCENT
 
 Exit if the disk is more than this percent full (default 100).
 


-m MEGABYTES
 
 Exit if there are less than this many megabytes free disk space (default 0).
 


-p PREFIX
 
 Store the data into files with this prefix (optional).
 


-t <yes/no>
 
 Collect tcpdump data.
 



***********
ENVIRONMENT
***********


This tool does not use any environment variables.


*******************
SYSTEM REQUIREMENTS
*******************


This tool requires Bash v3 or newer and assumes that these programs
are installed, in the PATH, and executable: sysctl, top, vmstat, iostat,
mpstat, lsof, mysql, mysqladmin, df, netstat, pidof, flock, and others
depending on what command-line options are specified.  If some of those
programs are not available, the tool will still run but may print warnings.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-collect <http://www.percona.com/bugs/pt-collect>`_.

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


This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Inc.
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


pt-collect 1.0.1

