
################
pt-mysql-summary
################

.. highlight:: perl


****
NAME
****


pt-mysql-summary - Summarize MySQL information in a nice way.


********
SYNOPSIS
********


Usage: pt-mysql-summary [MYSQL-OPTIONS]

pt-mysql-summary conveniently summarizes the status and configuration of a
MySQL database server so that you can learn about it at a glance.  It is not
a tuning tool or diagnosis tool.  It produces a report that is easy to diff
and can be pasted into emails without losing the formatting.  It should work
well on any modern UNIX systems.


*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-mysql-summary is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-mysql-summary <http://www.percona.com/bugs/pt-mysql-summary>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-mysql-summary works by connecting to a MySQL database server and querying
it for status and configuration information.  It saves these bits of data
into files in /tmp, and then formats them neatly with awk and other scripting
languages.

To use, simply execute it.  Optionally add the same command-line options
you would use to connect to MySQL, like  \ ``pt-mysql-summary --user=foo``\ .

The tool interacts minimally with the server upon which it runs.  It assumes
that you'll run it on the same server you're inspecting, and therefore it
assumes that it will be able to find the my.cnf configuration file, for
example.  However, it should degrade gracefully if this is not the case.
Note, however, that its output does not indicate which information comes from
the MySQL database and which comes from the host operating system, so it is
possible for confusing output to be generated if you run the tool on one
server and direct it to connect to a MySQL database server running on another
server.


**************
Fuzzy-Rounding
**************


Many of the outputs from this tool are deliberately rounded to show their
magnitude but not the exact detail.  This is called fuzzy-rounding. The idea
is that it doesn't matter whether a server is running 918 queries per second
or 921 queries per second; such a small variation is insignificant, and only
makes the output hard to compare to other servers.  Fuzzy-rounding rounds in
larger increments as the input grows.  It begins by rounding to the nearest 5,
then the nearest 10, nearest 25, and then repeats by a factor of 10 larger
(50, 100, 250), and so on, as the input grows.


*******
OPTIONS
*******


This tool does not have any command-line options of its own.  All options
are passed to \ ``mysql``\ .


***********
ENVIRONMENT
***********


This tool does not use any environment variables.


*******************
SYSTEM REQUIREMENTS
*******************


This tool requires Bash v3 or newer.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-mysql-summary <http://www.percona.com/bugs/pt-mysql-summary>`_.

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


pt-mysql-summary 1.0.1

