
######
pt-usl
######

.. highlight:: perl


****
NAME
****


pt-usl - Model Universal Scalability Law.


********
SYNOPSIS
********


Usage: pt-usl [OPTION...]


***********
DESCRIPTION
***********


This tool is based on Neil Gunther's book Guerrilla Capacity Planning.


****
TODO
****



.. code-block:: perl

    * Need to make it optionally make logarithmic X axis graph.  Also, apply
      -i and -n and so on in the main body, not in the converter itself,
      so that I can convert a file and then manipulate it separately.
 
    * I want it to entirely skip samples that have too-large concurrency, as
      defined by -m.  I don't want it to just average the concurrency across the
      other samples; it will introduce skew into the throughput for that sample,
      too.



***********
DOWNLOADING
***********


Visit `http://www.percona.com/software/ <http://www.percona.com/software/>`_ to download the latest release of
Percona Toolkit.  Or, to get the latest release from the command line:


.. code-block:: perl

    wget percona.com/latest/percona-toolkit/PKG


Replace \ ``PKG``\  with \ ``tar``\ , \ ``rpm``\ , or \ ``deb``\  to download the package in that
format.  You can also get individual tools from the latest release:


.. code-block:: perl

    wget percona.com/latest/percona-toolkit/TOOL


Replace \ ``TOOL``\  with the name of any tool.


***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-usl ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


*******************
SYSTEM REQUIREMENTS
*******************


You need Bash.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-usl <http://www.percona.com/bugs/pt-usl>`_.

Please report bugs at `https://bugs.launchpad.net/percona-toolkit <https://bugs.launchpad.net/percona-toolkit>`_.
Include the following information in your bug report:


\* Complete command-line used to run the tool



\* Tool "--version"



\* MySQL version of all servers involved



\* Output from the tool including STDERR



\* Input files (log/dump/config files, etc.)



If possible, include debugging output by running the tool with \ ``PTDEBUG``\ ;
see "ENVIRONMENT".


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


Percona Toolkit v1.0.0 released 2011-08-01

