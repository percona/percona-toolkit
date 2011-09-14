.. program:: pt-mext

====================
 :program:`pt-mext`
====================

.. highlight:: perl


NAME
====

 :program:`pt-mext` - Look at many samples of |MySQL| \ ``SHOW GLOBAL STATUS``\  side-by-side.


SYNOPSIS
========


Usage
-----

::

   pt-mext [OPTIONS] -- COMMAND

:program:`pt-mext` columnizes repeated output from a program like mysqladmin extended.

Get output from \ ``mysqladmin``\ :


.. code-block:: perl

    pt-mext -r -- mysqladmin ext -i10 -c3"


Get output from a file:


.. code-block:: perl

    pt-mext -r -- cat mysqladmin-output.txt


RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

:program:`pt-mext` is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-mext <http://www.percona.com/bugs/pt-mext>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

:program:`pt-mext` executes the \ ``COMMAND``\  you specify, and reads through the result one line at a time.  It places each line into a temporary file.  When it finds a
blank line, it assumes that a new sample of SHOW GLOBAL STATUS is starting,
and it creates a new temporary file.  At the end of this process, it has a
number of temporary files.  It joins the temporary files together side-by-side
and prints the result.  If the "-r" option is given, it first subtracts
each sample from the one after it before printing results.


OPTIONS
=======



-r
 
 Relative: subtract each column from the previous column.
 



ENVIRONMENT
===========


This tool does not use any environment variables.


SYSTEM REQUIREMENTS
===================


This tool requires the Bourne shell (\ */bin/sh*\ ) and the seq program.


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-mext <http://www.percona.com/bugs/pt-mext>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.


AUTHORS
=======


*Baron Schwartz*

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2010 Baron Schwartz, 2011 Percona Inc.
Feedback and improvements are welcome.


VERSION
=======

:program:`pt-mext` 1.0.1

