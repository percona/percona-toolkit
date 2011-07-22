
################
pt-query-advisor
################

.. highlight:: perl


****
NAME
****


pt-query-advisor - Analyze queries and advise on possible problems.


********
SYNOPSIS
********


Usage: pt-query-advisor [OPTION...] [FILE]

pt-query-advisor analyzes queries and advises on possible problems.
Queries are given either by specifying slowlog files, --query, or --review.


.. code-block:: perl

    # Analyzer all queries in the given slowlog
    pt-query-advisor /path/to/slow-query.log
 
    # Get queries from tcpdump using pt-query-digest
    pt-query-digest --type tcpdump.txt --print --no-report | pt-query-advisor
 
    # Get queries from a general log
    pt-query-advisor --type genlog mysql.log



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-query-advisor simply reads queries and examines them, and is thus
very low risk.

At the time of this release there is a bug that may cause an infinite (or
very long) loop when parsing very large queries.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-query-advisor <http://www.percona.com/bugs/pt-query-advisor>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-query-advisor examines queries and applies rules to them, trying to
find queries that look bad according to the rules.  It reports on
queries that match the rules, so you can find bad practices or hidden
problems in your SQL.  By default, it accepts a MySQL slow query log
as input.


*****
RULES
*****


These are the rules that pt-query-advisor will apply to the queries it
examines.  Each rule has three bits of information: an ID, a severity
and a description.

The rule's ID is its identifier.  We use a seven-character ID, and the
naming convention is three characters, a period, and a three-digit
number.  The first three characters are sort of an abbreviation of the
general class of the rule.  For example, ALI.001 is some rule related
to how the query uses aliases.

The rule's severity is an indication of how important it is that this
rule matched a query.  We use NOTE, WARN, and CRIT to denote these
levels.

The rule's description is a textual, human-readable explanation of
what it means when a query matches this rule.  Depending on the
verbosity of the report you generate, you will see more of the text in
the description.  By default, you'll see only the first sentence,
which is sort of a terse synopsis of the rule's meaning.  At a higher
verbosity, you'll see subsequent sentences.


ALI.001
 
 severity: note
 
 Aliasing without the AS keyword.  Explicitly using the AS keyword in
 column or table aliases, such as "tbl AS alias," is more readable
 than implicit aliases such as "tbl alias".
 


ALI.002
 
 severity: warn
 
 Aliasing the '\*' wildcard.  Aliasing a column wildcard, such as
 "SELECT tbl.\* col1, col2" probably indicates a bug in your SQL.
 You probably meant for the query to retrieve col1, but instead it
 renames the last column in the \*-wildcarded list.
 


ALI.003
 
 severity: note
 
 Aliasing without renaming.  The table or column's alias is the same as
 its real name, and the alias just makes the query harder to read.
 


ARG.001
 
 severity: warn
 
 Argument with leading wildcard.  An argument has a leading
 wildcard character, such as "%foo".  The predicate with this argument
 is not sargable and cannot use an index if one exists.
 


ARG.002
 
 severity: note
 
 LIKE without a wildcard.  A LIKE pattern that does not include a
 wildcard is potentially a bug in the SQL.
 


CLA.001
 
 severity: warn
 
 SELECT without WHERE.  The SELECT statement has no WHERE clause.
 


CLA.002
 
 severity: note
 
 ORDER BY RAND().  ORDER BY RAND() is a very inefficient way to
 retrieve a random row from the results.
 


CLA.003
 
 severity: note
 
 LIMIT with OFFSET.  Paginating a result set with LIMIT and OFFSET is
 O(n^2) complexity, and will cause performance problems as the data
 grows larger.
 


CLA.004
 
 severity: note
 
 Ordinal in the GROUP BY clause.  Using a number in the GROUP BY clause,
 instead of an expression or column name, can cause problems if the
 query is changed.
 


CLA.005
 
 severity: warn
 
 ORDER BY constant column.
 


CLA.006
 
 severity: warn
 
 GROUP BY or ORDER BY different tables will force a temp table and filesort.
 


CLA.007
 
 severity: warn
 
 ORDER BY different directions prevents index from being used. All tables
 in the ORDER BY clause must be either ASC or DESC, else MySQL cannot use
 an index.
 


COL.001
 
 severity: note
 
 SELECT \*.  Selecting all columns with the \* wildcard will cause the
 query's meaning and behavior to change if the table's schema
 changes, and might cause the query to retrieve too much data.
 


COL.002
 
 severity: note
 
 Blind INSERT.  The INSERT or REPLACE query doesn't specify the
 columns explicitly, so the query's behavior will change if the
 table's schema changes; use "INSERT INTO tbl(col1, col2) VALUES..."
 instead.
 


LIT.001
 
 severity: warn
 
 Storing an IP address as characters.  The string literal looks like
 an IP address, but is not an argument to INET_ATON(), indicating that
 the data is stored as characters instead of as integers.  It is
 more efficient to store IP addresses as integers.
 


LIT.002
 
 severity: warn
 
 Unquoted date/time literal.  A query such as "WHERE col<2010-02-12"
 is valid SQL but is probably a bug; the literal should be quoted.
 


KWR.001
 
 severity: note
 
 SQL_CALC_FOUND_ROWS is inefficient.  SQL_CALC_FOUND_ROWS can cause
 performance problems because it does not scale well; use
 alternative strategies to build functionality such as paginated
 result screens.
 


JOI.001
 
 severity: crit
 
 Mixing comma and ANSI joins.  Mixing comma joins and ANSI joins
 is confusing to humans, and the behavior differs between some
 MySQL versions.
 


JOI.002
 
 severity: crit
 
 A table is joined twice.  The same table appears at least twice in the
 FROM clause.
 


JOI.003
 
 severity: warn
 
 Reference to outer table column in WHERE clause prevents OUTER JOIN,
 implicitly converts to INNER JOIN.
 


JOI.004
 
 severity: warn
 
 Exclusion join uses wrong column in WHERE.  The exclusion join (LEFT
 OUTER JOIN with a WHERE clause that is satisfied only if there is no row in
 the right-hand table) seems to use the wrong column in the WHERE clause.  A
 query such as "... FROM l LEFT OUTER JOIN r ON l.l=r.r WHERE r.z IS NULL"
 probably ought to list r.r in the WHERE IS NULL clause.
 


RES.001
 
 severity: warn
 
 Non-deterministic GROUP BY.  The SQL retrieves columns that are
 neither in an aggregate function nor the GROUP BY expression, so
 these values will be non-deterministic in the result.
 


RES.002
 
 severity: warn
 
 LIMIT without ORDER BY.  LIMIT without ORDER BY causes
 non-deterministic results, depending on the query execution plan.
 


STA.001
 
 severity: note
 
 != is non-standard.  Use the <> operator to test for inequality.
 


SUB.001
 
 severity: crit
 
 IN() and NOT IN() subqueries are poorly optimized.  MySQL executes the subquery
 as a dependent subquery for each row in the outer query.  This is a frequent
 cause of serious performance problems.  This might change version 6.0 of MySQL,
 but for versions 5.1 and older, the query should be rewritten as a JOIN or a
 LEFT OUTER JOIN, respectively.
 



*******
OPTIONS
*******


"--query" and "--review" are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
 runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
 binmode on STDOUT without the utf8 layer, and runs SET NAMES after
 connecting to MySQL.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--[no]continue-on-error
 
 default: yes
 
 Continue working even if there is an error.
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX
 operating systems only.
 


--database
 
 short form: -D; type: string
 
 Connect to this database.  This is also used as the default database
 for "--[no]show-create-table" if a query does not use database-qualified
 tables.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--group-by
 
 type: string; default: rule_id
 
 Group items in the report by this attribute.  Possible attributes are:
 
 
 .. code-block:: perl
 
     ATTRIBUTE GROUPS
     ========= ==========================================================
     rule_id   Items matching the same rule ID
     query_id  Queries with the same ID (the same fingerprint)
     none      No grouping, report each query and its advice individually
 
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--ignore-rules
 
 type: hash
 
 Ignore these rule IDs.
 
 Specify a comma-separated list of rule IDs (e.g. LIT.001,RES.002,etc.)
 to ignore. Currently, the rule IDs are case-sensitive and must be uppercase.
 


--password
 
 short form: -p; type: string
 
 Password to use when connecting.
 


--pid
 
 type: string
 
 Create the given PID file when daemonized.  The file contains the process
 ID of the daemonized instance.  The PID file is removed when the
 daemonized instance exits.  The program checks for the existence of the
 PID file when starting; if it exists and the process with the matching PID
 exists, the program exits.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--print-all
 
 Print all queries, even those that do not match any rules.  With
 "--group-by" \ ``none``\ , non-matching queries are printed in the main report
 and profile.  For other "--group-by" values, non-matching queries are only
 printed in the profile.  Non-matching queries have zeros for \ ``NOTE``\ , \ ``WARN``\ 
 and \ ``CRIT``\  in the profile.
 


--query
 
 type: string
 
 Analyze this single query and ignore files and STDIN.  This option
 allows you to supply a single query on the command line.  Any files
 also specified on the command line are ignored.
 


--report-format
 
 type: string; default: compact
 
 Type of report format: full or compact.  In full mode, every query's
 report contains the description of the rules it matched, even if this
 information was previously displayed.  In compact mode, the repeated
 information is suppressed, and only the rule ID is displayed.
 


--review
 
 type: DSN
 
 Analyze queries from this pt-query-digest query review table.
 


--sample
 
 type: int; default: 1
 
 How many samples of the query to show.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--[no]show-create-table
 
 default: yes
 
 Get \ ``SHOW CREATE TABLE``\  for each query's table.
 
 If host connection options are given (like "--host", "--port", etc.)
 then the tool will also get \ ``SHOW CREATE TABLE``\  for each query.  This
 information is needed for some rules like JOI.004.  If this option is
 disabled by specifying \ ``--no-show-create-table``\  then some rules may not
 be checked.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--type
 
 type: Array
 
 The type of input to parse (default slowlog).  The permitted types are
 slowlog and genlog.
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


--verbose
 
 short form: -v; cumulative: yes; default: 1
 
 Increase verbosity of output.  At the default level of verbosity, the
 program prints only the first sentence of each rule's description.  At
 higher levels, the program prints more of the description.  See also
 "--report-format".
 


--version
 
 Show version and exit.
 


--where
 
 type: string
 
 Apply this WHERE clause to the SELECT query on the "--review" table.
 



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
 
 Database that contains the query review table.
 


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
 
 Table to use as the query review table.
 


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

    PTDEBUG=1 pt-query-advisor ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-query-advisor <http://www.percona.com/bugs/pt-query-advisor>`_.

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


Baron Schwartz and Daniel Nichter


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


This program is copyright 2010-2011 Percona Inc.
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

