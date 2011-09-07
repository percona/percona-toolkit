.. program:: pt-mysql-summary

=============================
 :program:`pt-mysql-summary`
=============================

.. highlight:: perl


NAME
====

 :program:`pt-mysql-summary` - Summarize |MySQL| information in a nice way.


SYNOPSIS
========


Usage
-----

::

   pt-mysql-summary [MYSQL-OPTIONS]

:program:`pt-mysql-summary` conveniently summarizes the status and configuration of a
|MySQL| database server so that you can learn about it at a glance.  It is not
a tuning tool or diagnosis tool.  It produces a report that is easy to diff
and can be pasted into emails without losing the formatting.  It should work
well on any modern UNIX systems.


RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

 :program:`pt-mysql-summary` is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-mysql-summary <http://www.percona.com/bugs/pt-mysql-summary>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-mysql-summary` works by connecting to a |MySQL| database server and querying
it for status and configuration information.  It saves these bits of data
into files in /tmp, and then formats them neatly with awk and other scripting
languages.

To use, simply execute it.  Optionally add the same command-line options
you would use to connect to |MySQL|, like  \ ` pt-mysql-summary --user=foo``\ .

The tool interacts minimally with the server upon which it runs.  It assumes
that you'll run it on the same server you're inspecting, and therefore it
assumes that it will be able to find the my.cnf configuration file, for
example.  However, it should degrade gracefully if this is not the case.
Note, however, that its output does not indicate which information comes from
the |MySQL| database and which comes from the host operating system, so it is
possible for confusing output to be generated if you run the tool on one
server and direct it to connect to a |MySQL| database server running on another
server.


Fuzzy-Rounding
==============


Many of the outputs from this tool are deliberately rounded to show their
magnitude but not the exact detail.  This is called fuzzy-rounding. The idea
is that it doesn't matter whether a server is running 918 queries per second
or 921 queries per second; such a small variation is insignificant, and only
makes the output hard to compare to other servers.  Fuzzy-rounding rounds in
larger increments as the input grows.  It begins by rounding to the nearest 5,
then the nearest 10, nearest 25, and then repeats by a factor of 10 larger
(50, 100, 250), and so on, as the input grows.


OPTIONS
=======


This tool does not have any command-line options of its own.  All options
are passed to \ ``mysql``\ .


ENVIRONMENT
===========


This tool does not use any environment variables.


SYSTEM REQUIREMENTS
===================


This tool requires Bash v3 or newer.


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-mysql-summary <http://www.percona.com/bugs/pt-mysql-summary>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.


AUTHORS
=======


*Baron Schwartz*


COPYRIGHT
=========

This program is copyright 2010-2011 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.

VERSION
=======

:program:`pt-mysql-summary` 1.0.1

