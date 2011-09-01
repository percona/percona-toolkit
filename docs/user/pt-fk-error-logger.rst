
##################
pt-fk-error-logger
##################

.. highlight:: perl


****
NAME
****


pt-fk-error-logger - Extract and log MySQL foreign key errors.


********
SYNOPSIS
********


Usage: pt-fk-error-logger [OPTION...] SOURCE_DSN

pt-fk-error-logger extracts and saves information about the most recent foreign
key errors in a MySQL server.

Print foreign key errors on host1:


.. code-block:: perl

    pt-fk-error-logger h=host1


Save foreign key errors on host1 to db.foreign_key_errors table on host2:


.. code-block:: perl

   pt-fk-error-logger h=host1 --dest h=host1,D=db,t=foreign_key_errors



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-fk-error-logger is read-only unless you specify "--dest".  It should be
very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-fk-error-logger <http://www.percona.com/bugs/pt-fk-error-logger>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-fk-error-logger prints or saves the foreign key errors text from
\ ``SHOW INNODB STATUS``\ .  The errors are not parsed or interpreted in any
way.  Foreign key errors are uniquely identified by their timestamp.
Only new (more recent) errors are printed or saved.


******
OUTPUT
******


If "--print" is given or no "--dest" is given, then pt-fk-error-logger
prints the foreign key error text to STDOUT exactly as it appeared in
\ ``SHOW INNODB STATUS``\ .


*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
 NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
 without the utf8 layer, and runs SET NAMES after connecting to MySQL.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX operating systems only.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--dest
 
 type: DSN
 
 DSN for where to store foreign key errors; specify at least a database (D) and table (t).
 
 Missing values are filled in with the same values from the source host, so you
 can usually omit most parts of this argument if you're storing foreign key
 errors on the same server on which they happen.
 
 The following table is suggested:
 
 
 .. code-block:: perl
 
   CREATE TABLE foreign_key_errors (
     ts datetime NOT NULL,
     error text NOT NULL,
     PRIMARY KEY (ts),
   )
 
 
 The only information saved is the timestamp and the foreign key error text.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--interval
 
 type: time; default: 0
 
 How often to check for foreign key errors.
 


--log
 
 type: string
 
 Print all output to this file when daemonized.
 


--password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


--pid
 
 type: string
 
 Create the given PID file when daemonized.  The file contains the process ID of
 the daemonized instance.  The PID file is removed when the daemonized instance
 exits.  The program checks for the existence of the PID file when starting; if
 it exists and the process with the matching PID exists, the program exits.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--print
 
 Print results on standard output.  See "OUTPUT" for more.
 


--run-time
 
 type: time
 
 How long to run before exiting.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


--version
 
 Show version and exit.
 



***********
DSN OPTIONS
***********


These DSN options are used to create a DSN.  Each option is given like
\ ``option=value``\ .  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the \ ``=``\  and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the percona-toolkit manpage for full details.


\* A
 
 dsn: charset; copy: yes
 
 Default character set.
 


\* D
 
 dsn: database; copy: yes
 
 Default database.
 


\* F
 
 dsn: mysql_read_default_file; copy: yes
 
 Only read default options from the given file
 


\* h
 
 dsn: host; copy: yes
 
 Connect to host.
 


\* p
 
 dsn: password; copy: yes
 
 Password to use when connecting.
 


\* P
 
 dsn: port; copy: yes
 
 Port number to use for connection.
 


\* S
 
 dsn: mysql_socket; copy: yes
 
 Socket file to use for connection.
 


\* t
 
 Table in which to store foreign key errors.
 


\* u
 
 dsn: user; copy: yes
 
 User for login if not current user.
 



***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-fk-error-logger ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-fk-error-logger <http://www.percona.com/bugs/pt-fk-error-logger>`_.

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


Daniel Nichter


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


This program is copyright 2011 Percona Inc.
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


pt-fk-error-logger 1.0.1

