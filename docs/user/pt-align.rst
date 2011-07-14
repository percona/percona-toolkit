
########
pt-align
########

.. highlight:: perl


****
NAME
****


pt-align - Read lines and split them into words.


********
SYNOPSIS
********


Usage: pt-align [OPTION...]


***********
DESCRIPTION
***********


This program reads in lines and splits them into words.  It counts how many
words each line has, and if there is one number that predominates, it assumes
this is the number of words in each line.  Then it discards all lines that
don't have that many words, and looks at the 2nd line that DOES.  It assumes
this is the first non-header line.  Based on whether each word looks numeric
or not, it decides on column alignment.  Finally, it goes through and decides
how wide each column should be, and then prints them out.

This is useful for things like aligning the output of vmstat or iostat so it
is easier to read.


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

    PTDEBUG=1 pt-align ... > FILE 2>&1


Be careful: debugging output is voluminous and can generate several megabytes
of output.


*******************
SYSTEM REQUIREMENTS
*******************


You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.


****
BUGS
****


For a list of known bugs, see `http://www.percona.com/bugs/pt-align <http://www.percona.com/bugs/pt-align>`_.

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

