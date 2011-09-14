.. program:: pt-sift

====================
 :program:`pt-sift`
====================

.. highlight:: perl


NAME
====

 :program:`pt-sift` - Browses files created by pt-collect.


SYNOPSIS
========


Usage
-----

::

   pt-sift FILE|PREFIX|DIRECTORY

:program:`pt-sift` browses the files created by :program:`pt-collect`.  If you specify a
FILE or PREFIX, it browses only files with that prefix.  If you specify a
DIRECTORY, then it browses all files within that directory.


RISKS
=====


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.
 :program:`pt-sift` is a read-only tool.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-sift <http://www.percona.com/bugs/pt-sift>`_.

See also :ref:`bugs` for more information on filing bugs and getting help.


DESCRIPTION
===========

 :program:`pt-sift` downloads other tools that it might need, such as pt-diskstats,
and then makes a list of the unique timestamp prefixes of all the files in
the directory, as written by the pt-collect tool.  If the user specified
a timestamp on the command line, then it begins with that sample of data;
otherwise it begins by showing a list of the timestamps and prompting for
a selection.  Thereafter, it displays a summary of the selected sample, and
the user can navigate and inspect with keystrokes.  The keystroke commands
you can use are as follows:


  * ``d``
 
 Sets the action to start the pt-diskstats tool on the sample's disk
 performance statistics.
 


  * ``i``
 
 Sets the action to view the first INNODB STATUS sample in less.
 


  * ``m``
 
 Displays the first 4 samples of SHOW STATUS counters side by side with the
 pt-mext tool.
 


  * ``n``
 
 Summarizes the first sample of netstat data in two ways: by originating host,
 and by connection state.
 


  * ``j``
 
 Select the next timestamp as the active sample.
 


  * ``k``
 
 Select the previous timestamp as the active sample.
 


  * ``q``
 
 Quit the program.
 


  * ``1``
 
 Sets the action for each sample to the default, which is to view a summary
 of the sample.
 


  * ``0``
 
 Sets the action to just list the files in the sample.
 


  * ``*``
 
 Sets the action to view all of the samples's files in the less program.
 



OPTIONS
=======


This tool does not have any command-line options.


ENVIRONMENT
===========


This tool does not use any environment variables.


SYSTEM REQUIREMENTS
===================


This tool requires Bash v3 and the following programs: pt-diskstats, pt-pmp,
pt-mext, and align (from Aspersa).  If these programs are not in your PATH,
they will be fetched from the Internet if curl is available.


BUGS
====


For a list of known bugs, see `http://www.percona.com/bugs/pt-sift <http://www.percona.com/bugs/pt-sift>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.


AUTHORS
=======

*Baron Schwartz*


COPYRIGHT, LICENSE, AND WARRANTY
================================


This program is copyright 2010-2011 *Baron Schwartz*, 2011 Percona Inc.
Feedback and improvements are welcome.


VERSION
=======

:program:`pt-sift` 1.0.1

