
#######
pt-find
#######

.. highlight:: perl


****
NAME
****


pt-find - Find MySQL tables and execute actions, like GNU find.


********
SYNOPSIS
********


Usage: pt-find [OPTION...] [DATABASE...]

pt-find searches for MySQL tables and executes actions, like GNU find.  The
default action is to print the database and table name.

Find all tables created more than a day ago, which use the MyISAM engine, and
print their names:


.. code-block:: perl

   pt-find --ctime +1 --engine MyISAM


Find InnoDB tables that haven't been updated in a month, and convert them to
MyISAM storage engine (data warehousing, anyone?):


.. code-block:: perl

   pt-find --mtime +30 --engine InnoDB --exec "ALTER TABLE %D.%N ENGINE=MyISAM"


Find tables created by a process that no longer exists, following the
name_sid_pid naming convention, and remove them.


.. code-block:: perl

   pt-find --connection-id '\D_\d+_(\d+)$' --server-id '\D_(\d+)_\d+$' --exec-plus "DROP TABLE %s"


Find empty tables in the test and junk databases, and delete them:


.. code-block:: perl

   pt-find --empty junk test --exec-plus "DROP TABLE %s"


Find tables more than five gigabytes in total size:


.. code-block:: perl

   pt-find --tablesize +5G


Find all tables and print their total data and index size, and sort largest
tables first (sort is a different program, by the way).


.. code-block:: perl

   pt-find --printf "%T\t%D.%N\n" | sort -rn


As above, but this time, insert the data back into the database for posterity:


.. code-block:: perl

   pt-find --noquote --exec "INSERT INTO sysdata.tblsize(db, tbl, size) VALUES('%D', '%N', %T)"



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-find only reads and prints information by default, but "--exec" and
"--exec-plus" can execute user-defined SQL.  You should be as careful with it
as you are with any command-line tool that can execute queries against your
database.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-find <http://www.percona.com/bugs/pt-find>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-find looks for MySQL tables that pass the tests you specify, and executes
the actions you specify.  The default action is to print the database and table
name to STDOUT.

pt-find is simpler than GNU find.  It doesn't allow you to specify
complicated expressions on the command line.

pt-find uses SHOW TABLES when possible, and SHOW TABLE STATUS when needed.


************
OPTION TYPES
************


There are three types of options: normal options, which determine some behavior
or setting; tests, which determine whether a table should be included in the
list of tables found; and actions, which do something to the tables pt-find
finds.

pt-find uses standard Getopt::Long option parsing, so you should use double
dashes in front of long option names, unlike GNU find.


*******
OPTIONS
*******


This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--case-insensitive
 
 Specifies that all regular expression searches are case-insensitive.
 


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
 


--day-start
 
 Measure times (for "--mmin", etc) from the beginning of today rather than
 from the current time.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--or
 
 Combine tests with OR, not AND.
 
 By default, tests are evaluated as though there were an AND between them.  This
 option switches it to OR.
 
 Option parsing is not implemented by pt-find itself, so you cannot specify
 complicated expressions with parentheses and mixtures of OR and AND.
 


--password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


--pid
 
 type: string
 
 Create the given PID file.  The file contains the process ID of the script.
 The PID file is removed when the script exits.  Before starting, the script
 checks if the PID file already exists.  If it does not, then the script creates
 and writes its own PID to it.  If it does, then the script checks the following:
 if the file contains a PID and a process is running with that PID, then
 the script dies; or, if there is no process running with that PID, then the
 script overwrites the file with its own PID and starts; else, if the file
 contains no PID, then the script dies.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--[no]quote
 
 default: yes
 
 Quotes MySQL identifier names with MySQL's standard backtick character.
 
 Quoting happens after tests are run, and before actions are run.
 


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
 


TESTS
=====


Most tests check some criterion against a column of SHOW TABLE STATUS output.
Numeric arguments can be specified as +n for greater than n, -n for less than n,
and n for exactly n.  All numeric options can take an optional suffix multiplier
of k, M or G (1_024, 1_048_576, and 1_073_741_824 respectively).  All patterns
are Perl regular expressions (see 'man perlre') unless specified as SQL LIKE
patterns.

Dates and times are all measured relative to the same instant, when pt-find
first asks the database server what time it is.  All date and time manipulation
is done in SQL, so if you say to find tables modified 5 days ago, that
translates to SELECT DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 5 DAY).  If you
specify "--day-start", if course it's relative to CURRENT_DATE instead.

However, table sizes and other metrics are not consistent at an instant in
time.  It can take some time for MySQL to process all the SHOW queries, and
pt-find can't do anything about that.  These measurements are as of the
time they're taken.

If you need some test that's not in this list, file a bug report and I'll
enhance pt-find for you.  It's really easy.


--autoinc
 
 type: string; group: Tests
 
 Table's next AUTO_INCREMENT is n.  This tests the Auto_increment column.
 


--avgrowlen
 
 type: size; group: Tests
 
 Table avg row len is n bytes.  This tests the Avg_row_length column.
 The specified size can be "NULL" to test where Avg_row_length IS NULL.
 


--checksum
 
 type: string; group: Tests
 
 Table checksum is n.  This tests the Checksum column.
 


--cmin
 
 type: size; group: Tests
 
 Table was created n minutes ago.  This tests the Create_time column.
 


--collation
 
 type: string; group: Tests
 
 Table collation matches pattern.  This tests the Collation column.
 


--column-name
 
 type: string; group: Tests
 
 A column name in the table matches pattern.
 


--column-type
 
 type: string; group: Tests
 
 A column in the table matches this type (case-insensitive).
 
 Examples of types are: varchar, char, int, smallint, bigint, decimal, year,
 timestamp, text, enum.
 


--comment
 
 type: string; group: Tests
 
 Table comment matches pattern.  This tests the Comment column.
 


--connection-id
 
 type: string; group: Tests
 
 Table name has nonexistent MySQL connection ID.  This tests the table name for
 a pattern.  The argument to this test must be a Perl regular expression that
 captures digits like this: (\d+).  If the table name matches the pattern,
 these captured digits are taken to be the MySQL connection ID of some process.
 If the connection doesn't exist according to SHOW FULL PROCESSLIST, the test
 returns true.  If the connection ID is greater than pt-find's own
 connection ID, the test returns false for safety.
 
 Why would you want to do this?  If you use MySQL statement-based replication,
 you probably know the trouble temporary tables can cause.  You might choose to
 work around this by creating real tables with unique names, instead of
 temporary tables.  One way to do this is to append your connection ID to the
 end of the table, thusly: scratch_table_12345.  This assures the table name is
 unique and lets you have a way to find which connection it was associated
 with.  And perhaps most importantly, if the connection no longer exists, you
 can assume the connection died without cleaning up its tables, and this table
 is a candidate for removal.
 
 This is how I manage scratch tables, and that's why I included this test in
 pt-find.
 
 The argument I use to "--connection-id" is "\D_(\d+)$".  That finds tables
 with a series of numbers at the end, preceded by an underscore and some
 non-number character (the latter criterion prevents me from examining tables
 with a date at the end, which people tend to do: baron_scratch_2007_05_07 for
 example).  It's better to keep the scratch tables separate of course.
 
 If you do this, make sure the user pt-find runs as has the PROCESS privilege!
 Otherwise it will only see connections from the same user, and might think some
 tables are ready to remove when they're still in use.  For safety, pt-find
 checks this for you.
 
 See also "--server-id".
 


--createopts
 
 type: string; group: Tests
 
 Table create option matches pattern.  This tests the Create_options column.
 


--ctime
 
 type: size; group: Tests
 
 Table was created n days ago.  This tests the Create_time column.
 


--datafree
 
 type: size; group: Tests
 
 Table has n bytes of free space.  This tests the Data_free column.
 The specified size can be "NULL" to test where Data_free IS NULL.
 


--datasize
 
 type: size; group: Tests
 
 Table data uses n bytes of space.  This tests the Data_length column.
 The specified size can be "NULL" to test where Data_length IS NULL.
 


--dblike
 
 type: string; group: Tests
 
 Database name matches SQL LIKE pattern.
 


--dbregex
 
 type: string; group: Tests
 
 Database name matches this pattern.
 


--empty
 
 group: Tests
 
 Table has no rows.  This tests the Rows column.
 


--engine
 
 type: string; group: Tests
 
 Table storage engine matches this pattern.  This tests the Engine column, or in
 earlier versions of MySQL, the Type column.
 


--function
 
 type: string; group: Tests
 
 Function definition matches pattern.
 


--indexsize
 
 type: size; group: Tests
 
 Table indexes use n bytes of space.  This tests the Index_length column.
 The specified size can be "NULL" to test where Index_length IS NULL.
 


--kmin
 
 type: size; group: Tests
 
 Table was checked n minutes ago.  This tests the Check_time column.
 


--ktime
 
 type: size; group: Tests
 
 Table was checked n days ago.  This tests the Check_time column.
 


--mmin
 
 type: size; group: Tests
 
 Table was last modified n minutes ago.  This tests the Update_time column.
 


--mtime
 
 type: size; group: Tests
 
 Table was last modified n days ago.  This tests the Update_time column.
 


--procedure
 
 type: string; group: Tests
 
 Procedure definition matches pattern.
 


--rowformat
 
 type: string; group: Tests
 
 Table row format matches pattern.  This tests the Row_format column.
 


--rows
 
 type: size; group: Tests
 
 Table has n rows.  This tests the Rows column.
 The specified size can be "NULL" to test where Rows IS NULL.
 


--server-id
 
 type: string; group: Tests
 
 Table name contains the server ID.  If you create temporary tables with the
 naming convention explained in "--connection-id", but also add the server ID of the
 server on which the tables are created, then you can use this pattern match to
 ensure tables are dropped only on the server they're created on.  This prevents
 a table from being accidentally dropped on a slave while it's in use (provided
 that your server IDs are all unique, which they should be for replication to
 work).
 
 For example, on the master (server ID 22) you create a table called
 scratch_table_22_12345.  If you see this table on the slave (server ID 23), you
 might think it can be dropped safely if there's no such connection 12345.  But
 if you also force the name to match the server ID with \ ``--server-id '\D_(\d+)_\d+$'``\ ,
 the table won't be dropped on the slave.
 


--tablesize
 
 type: size; group: Tests
 
 Table uses n bytes of space.  This tests the sum of the Data_length and
 Index_length columns.
 


--tbllike
 
 type: string; group: Tests
 
 Table name matches SQL LIKE pattern.
 


--tblregex
 
 type: string; group: Tests
 
 Table name matches this pattern.
 


--tblversion
 
 type: size; group: Tests
 
 Table version is n.  This tests the Version column.
 


--trigger
 
 type: string; group: Tests
 
 Trigger action statement matches pattern.
 


--trigger-table
 
 type: string; group: Tests
 
 "--trigger" is defined on table matching pattern.
 


--view
 
 type: string; group: Tests
 
 CREATE VIEW matches this pattern.
 



ACTIONS
=======


The "--exec-plus" action happens after everything else, but otherwise actions
happen in an indeterminate order.  If you need determinism, file a bug report
and I'll add this feature.


--exec
 
 type: string; group: Actions
 
 Execute this SQL with each item found.  The SQL can contain escapes and
 formatting directives (see "--printf").
 


--exec-dsn
 
 type: string; group: Actions
 
 Specify a DSN in key-value format to use when executing SQL with "--exec" and
 "--exec-plus".  Any values not specified are inherited from command-line
 arguments.
 


--exec-plus
 
 type: string; group: Actions
 
 Execute this SQL with all items at once.  This option is unlike "--exec".  There
 are no escaping or formatting directives; there is only one special placeholder
 for the list of database and table names, %s.  The list of tables found will be
 joined together with commas and substituted wherever you place %s.
 
 You might use this, for example, to drop all the tables you found:
 
 
 .. code-block:: perl
 
     DROP TABLE %s
 
 
 This is sort of like GNU find's "-exec command {} +" syntax.  Only it's not
 totally cryptic.  And it doesn't require me to write a command-line parser.
 


--print
 
 group: Actions
 
 Print the database and table name, followed by a newline.  This is the default
 action if no other action is specified.
 


--printf
 
 type: string; group: Actions
 
 Print format on the standard output, interpreting '\' escapes and '%'
 directives.  Escapes are backslashed characters, like \n and \t.  Perl
 interprets these, so you can use any escapes Perl knows about.  Directives are
 replaced by %s, and as of this writing, you can't add any special formatting
 instructions, like field widths or alignment (though I'm musing over ways to do
 that).
 
 Here is a list of the directives.  Note that most of them simply come from
 columns of SHOW TABLE STATUS.  If the column is NULL or doesn't exist, you get
 an empty string in the output.  A % character followed by any character not in
 the following list is discarded (but the other character is printed).
 
 
 .. code-block:: perl
 
     CHAR DATA SOURCE        NOTES
     ---- ------------------ ------------------------------------------
     a    Auto_increment
     A    Avg_row_length
     c    Checksum
     C    Create_time
     D    Database           The database name in which the table lives
     d    Data_length
     E    Engine             In older versions of MySQL, this is Type
     F    Data_free
     f    Innodb_free        Parsed from the Comment field
     I    Index_length
     K    Check_time
     L    Collation
     M    Max_data_length
     N    Name
     O    Comment
     P    Create_options
     R    Row_format
     S    Rows
     T    Table_length       Data_length+Index_length
     U    Update_time
     V    Version
 
 




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
 


\* u
 
 dsn: user; copy: yes
 
 User for login if not current user.
 



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


***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-find ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-find <http://www.percona.com/bugs/pt-find>`_.

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


This program is copyright 2007-2011 Baron Schwartz, 2011 Percona Inc.
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

