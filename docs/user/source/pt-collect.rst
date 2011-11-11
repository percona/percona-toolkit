
.. program:: pt-collect

=======================
 :program:`pt-collect`
=======================

.. highlight:: perl

NAME
====

:program:`pt-collect` - Collect information from a server for some period of time.

SYNOPSIS
========

Usage
-----

::

  pt-collect -d -g -i -o -s [OPTIONS] [-- MYSQL-OPTIONS]

:program:`pt-collect` tool gathers a variety of information about a system for a period of time.  It is typically executed when the stalk tool detects a condition and wants to collect information to assist in diagnosis.  Four options
must be specified on the command line: ``-dgios``.

RISKS
=====

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-collect` is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-collect <http://www.percona.com/bugs/pt-collect>`_.

See also "BUGS" for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-collect` creates a lock to ensure that only one instance runs at a time, and then saves a variety of performance and status data into files in the
configured directory.  Files are named with a timestamp so they can be grouped together.  The tool is MySQL-centric by default, and gathers quite a bit of diagnostic data that's useful for understanding the behavior of a MySQL database server.

Options after \ ``--``\  are passed to \ ``mysql``\  and \ ``mysqladmin``\ .

OPTIONS
=======

.. option:: -d DESTINATION (required)
 
   Where to store the resulting data; must already exist.

.. option:: -g <yes/no> (required)
 
   Collect GDB stack traces.
 
.. option:: -i INTERVAL (required)
 
   How many seconds to collect data.
 
.. option:: -o <yes/no> (required)
 
   Collect oprofile data; disables -s.
 
.. option:: -s <yes/no> (required)
 
   Collect strace data.
 
.. option:: -f PERCENT
 
   Exit if the disk is more than this percent full (default 100).
 
.. option:: -m MEGABYTES
 
   Exit if there are less than this many megabytes free disk space (default 0).
 
.. option:: -p PREFIX
 
   Store the data into files with this prefix (optional).
 
.. option:: -t <yes/no>
 
   Collect tcpdump data.
 
ENVIRONMENT
===========

This tool does not use any environment variables.

SYSTEM REQUIREMENTS
===================

This tool requires Bash v3 or newer and assumes that these programs
are installed, in the PATH, and executable: sysctl, top, vmstat, iostat,
mpstat, lsof, mysql, mysqladmin, df, netstat, pidof, flock, and others
depending on what command-line options are specified.  If some of those
programs are not available, the tool will still run but may print warnings.

AUTHORS
=======

Baron Schwartz

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

pt-collect 1.0.1

