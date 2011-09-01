
########
pt-stalk
########

.. highlight:: perl


****
NAME
****


pt-stalk - Wait for a condition to occur then begin collecting data.


********
SYNOPSIS
********


Usage: pt-stalk

pt-stalk watches for a condition to become true, and when it does, executes
a script.  By default it executes pt-collect, but that can be customized.
This tool is useful for gathering diagnostic data when an infrequent event
occurs, so an expert person can review the data later.


*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-stalk is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-stalk <http://www.percona.com/bugs/pt-stalk>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


Although pt-stalk comes pre-configured to do a specific thing, in general
this tool is just a skeleton script for the following flow of actions:


1.
 
 Loop infinitely, sleeping between iterations.
 


2.
 
 In each iteration, run some command and get the output.
 


3.
 
 If the command fails or the output is larger than the threshold,
 execute the collection script; but do not execute if the destination disk
 is too full.
 


By default, the tool is configured to execute mysqladmin extended-status and
extract the value of the Threads_connected variable; if this is greater than
100, it runs the collection script. This is really just placeholder code,
and almost certainly needs to be customized!

If the tool does execute the collection script, it will wait for a while
before checking and executing again.  This is to prevent a continuous
condition from causing a huge number of executions to fire off.

The name 'stalk' is because 'watch' is already taken, and 'stalk' is fun.


***********
CONFIGURING
***********


If the file \ *pt-stalk.conf*\  exists in the current working directory, then
"ENVIRONMENT" variables are imported from it.  For example, the config
file has the format:


.. code-block:: perl

    INTERVAL=10
    GDB=yes


See "ENVIRONMENT".


*******
OPTIONS
*******


This tool does not have any command-line options, but see
"ENVIRONMENT" and "CONFIGURING".


***********
ENVIRONMENT
***********


The following environment variables configure how, what, and when the tool
runs.  They are all optional and can be specified either on the command line
or in the \ *pt-stalk.conf*\  config file (see "CONFIGURING").


THRESHOLD (default 100)
 
 This is the max number of <whatever> we want to tolerate.
 


VARIABLE (default Threads_connected}
 
 This is the thing to check for.
 


CYCLES (default 1)
 
 How many times must the condition be met before the script will fire?
 


GDB (default no)
 
 Collect GDB stacktraces?
 


OPROFILE (default yes)
 
 Collect oprofile data?
 


STRACE (default no)
 
 Collect strace data?
 


TCPDUMP (default yes)
 
 Collect tcpdump data?
 


EMAIL
 
 Send mail to this list of addresses when the script triggers.
 


MYSQLOPTIONS
 
 Any options to pass to mysql/mysqladmin, such as -u, -p, etc
 


INTERVAL (default 30)
 
 This is the interval between checks.
 


MAYBE_EMPTY (default no)
 
 If the command you're running to detect the condition is allowed to return
 nothing (e.g. a grep line that might not even exist if there's no problem),
 then set this to "yes".
 


COLLECT (default ${HOME}/bin/pt-collect)
 
 This is the location of the 'collect' script.
 


DEST (default ${HOME}/collected/)
 
 This is where to store the collected data.
 


DURATION (default 30)
 
 How long to collect statistics data for?  Make sure that this isn't longer
 than SLEEP.
 


SLEEP (default DURATION \* 10)
 
 How long to sleep after collecting?
 


PCT_THRESHOLD (default 95)
 
 Bail out if the disk is more than this %full.
 


MB_THRESHOLD (default 100)
 
 Bail out if the disk has less than this many MB free.
 


PURGE (default 30)
 
 Remove samples after this many days.
 



*******************
SYSTEM REQUIREMENTS
*******************


This tool requires Bash v3 or newer.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-stalk <http://www.percona.com/bugs/pt-stalk>`_.

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


Baron Schwartz, Justin Swanhart, and Fernando Ipar


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


pt-stalk 1.0.1

