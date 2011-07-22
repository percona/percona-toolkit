
##########
pt-summary
##########

.. highlight:: perl


****
NAME
****


pt-summary - Summarize system information in a nice way.


********
SYNOPSIS
********


Usage: pt-summary

pt-summary conveniently summarizes the status and configuration of a server.
It is not a tuning tool or diagnosis tool.  It produces a report that is easy
to diff and can be pasted into emails without losing the formatting.  This
tool works well on Linux systems.

Download and run:


.. code-block:: perl

    wget http://aspersa.googlecode.com/svn/trunk/summary
    bash ./summary


Download and run in a single step:


.. code-block:: perl

    wget -O- http://aspersa.googlecode.com/svn/trunk/summary | bash



***********
DESCRIPTION
***********


pt-summary runs a large variety of commands to inspect system status and
configuration, saves the output into files in /tmp, and then runs Unix
commands on these results to format them nicely.  It works best when
executed as a privileged user, but will also work without privileges,
although some output might not be possible to generate without root.


*******
OPTIONS
*******


This tool does not have any command-line options.


***********
ENVIRONMENT
***********


The PT_SUMMARY_SKIP environment variable specifies a comma-separated list
of things to skip:


.. code-block:: perl

   MOUNT:   Don't print out mounted filesystems and disk fullness.
   NETWORK: Don't print out information on network controllers & config.
   PROCESS: Don't print out top processes and vmstat information.



*******************
SYSTEM REQUIREMENTS
*******************


This tool requires the Bourne shell (\ */bin/sh*\ ).


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-summary <http://www.percona.com/bugs/pt-summary>`_.

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


Baron Schwartz and Kevin van Zonneveld (http://kevin.vanzonneveld.net)


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


Percona Toolkit v1.0.0 released 2011-08-01

