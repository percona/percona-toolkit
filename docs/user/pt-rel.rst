
######
pt-rel
######

.. highlight:: perl


****
NAME
****


pt-rel - Relativize values to previous matching lines.


********
SYNOPSIS
********


Usage: pt-rel [FILES]

pt-rel matches lines and subtracts the value of the previous line's values
from the current line's values.  The lines must be text with numeric values
that repeat, varying only the values.


***********
DESCRIPTION
***********


For example, if the text is this:


.. code-block:: perl

   Mutex spin waits 0, rounds 99584819933, OS waits 437663963
   RW-shared spins 834337527, OS waits 20258150; RW-excl spins 1769749834
   Mutex spin waits 0, rounds 99591465498, OS waits 437698122
   RW-shared spins 834352175, OS waits 20259032; RW-excl spins 1769762980


Then the output will be:


.. code-block:: perl

   Mutex spin waits 0, rounds 99584819933, OS waits 437663963
   RW-shared spins 834337527, OS waits 20258150; RW-excl spins 1769749834
   Mutex spin waits 0, rounds 6645565, OS waits 34159
   RW-shared spins 14648, OS waits 882; RW-excl spins 13146


The first values (line 1) for "Mutex spin waits", "rounds", and "OS waits"
were subtracted from the second values (line 3); the same happened for values
from lines 2 and 4.


*******
OPTIONS
*******


This tool does not have any command-line options.


***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-rel ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


*******************
SYSTEM REQUIREMENTS
*******************


This tool requires Perl v5.8 or newer.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-rel <http://www.percona.com/bugs/pt-rel>`_.

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

