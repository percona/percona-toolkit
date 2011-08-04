
#################
pt-visual-explain
#################

.. highlight:: perl


****
NAME
****


pt-visual-explain - Format EXPLAIN output as a tree.


********
SYNOPSIS
********


Usage: pt-visual-explain [OPTION...] [FILE...]

pt-visual-explain transforms EXPLAIN output into a tree representation of
the query plan.  If FILE is given, input is read from the file(s).  With no
FILE, or when FILE is -, read standard input.

Examples:


.. code-block:: perl

   pt-visual-explain <file_containing_explain_output>
 
   pt-visual-explain -c <file_containing_query>
 
   mysql -e "explain select * from mysql.user" | pt-visual-explain



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-visual-explain is read-only and very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-visual-explain <http://www.percona.com/bugs/pt-visual-explain>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-visual-explain reverse-engineers MySQL's EXPLAIN output into a query
execution plan, which it then formats as a left-deep tree -- the same way the
plan is represented inside MySQL.  It is possible to do this by hand, or to read
EXPLAIN's output directly, but it requires patience and expertise.  Many people
find a tree representation more understandable.

You can pipe input into pt-visual-explain or specify a filename at the
command line, including the magical '-' filename, which will read from standard
input.  It can do two things with the input: parse it for something that looks
like EXPLAIN output, or connect to a MySQL instance and run EXPLAIN on the
input.

When parsing its input, pt-visual-explain understands three formats: tabular
like that shown in the mysql command-line client, vertical like that created by
using the \G line terminator in the mysql command-line client, and tab
separated.  It ignores any lines it doesn't know how to parse.

When executing the input, pt-visual-explain replaces everything in the input
up to the first SELECT keyword with 'EXPLAIN SELECT,' and then executes the
result.  You must specify "--connect" to execute the input as a query.

Either way, it builds a tree from the result set and prints it to standard
output.  For the following query,


.. code-block:: perl

  select * from sakila.film_actor join sakila.film using(film_id);


pt-visual-explain generates this query plan:


.. code-block:: perl

  JOIN
  +- Bookmark lookup
  |  +- Table
  |  |  table          film_actor
  |  |  possible_keys  idx_fk_film_id
  |  +- Index lookup
  |     key            film_actor->idx_fk_film_id
  |     possible_keys  idx_fk_film_id
  |     key_len        2
  |     ref            sakila.film.film_id
  |     rows           2
  +- Table scan
     rows           952
     +- Table
        table          film
        possible_keys  PRIMARY


The query plan is left-deep, depth-first search, and the tree's root is the
output node -- the last step in the execution plan.  In other words, read it
like this:


1
 
 Table scan the 'film' table, which accesses an estimated 952 rows.
 


2
 
 For each row, find matching rows by doing an index lookup into the
 film_actor->idx_fk_film_id index with the value from sakila.film.film_id, then a
 bookmark lookup into the film_actor table.
 


For more information on how to read EXPLAIN output, please see
`http://dev.mysql.com/doc/en/explain.html <http://dev.mysql.com/doc/en/explain.html>`_, and this talk titled "Query
Optimizer Internals and What's New in the MySQL 5.2 Optimizer," from Timour
Katchaounov, one of the MySQL developers:
`http://maatkit.org/presentations/katchaounov_timour.pdf <http://maatkit.org/presentations/katchaounov_timour.pdf>`_.


*******
MODULES
*******


This program is actually a runnable module, not just an ordinary Perl script.
In fact, there are two modules embedded in it.  This makes unit testing easy,
but it also makes it easy for you to use the parsing and tree-building
functionality if you want.

The ExplainParser package accepts a string and parses whatever it thinks looks
like EXPLAIN output from it.  The synopsis is as follows:


.. code-block:: perl

  require "pt-visual-explain";
  my $p    = ExplainParser->new();
  my $rows = $p->parse("some text");
  # $rows is an arrayref of hashrefs.


The ExplainTree package accepts a set of rows and turns it into a tree.  For
convenience, you can also have it delegate to ExplainParser and parse text for
you.  Here's the synopsis:


.. code-block:: perl

  require "pt-visual-explain";
  my $e      = ExplainTree->new();
  my $tree   = $e->parse("some text", \%options);
  my $output = $e->pretty_print($tree);
  print $tree;



*********
ALGORITHM
*********


This section explains the algorithm that converts EXPLAIN into a tree.  You may
be interested in reading this if you want to understand EXPLAIN more fully, or
trying to figure out how this works, but otherwise this section will probably
not make your life richer.

The tree can be built by examining the id, select_type, and table columns of
each row.  Here's what I know about them:

The id column is the sequential number of the select.  This does not indicate
nesting; it just comes from counting SELECT from the left of the SQL statement.
It's like capturing parentheses in a regular expression.  A UNION RESULT row
doesn't have an id, because it isn't a SELECT.  The source code actually refers
to UNIONs as a fake_lex, as I recall.

If two adjacent rows have the same id value, they are joined with the standard
single-sweep multi-join method.

The select_type column tells a) that a new sub-scope has opened b) what kind
of relationship the row has to the previous row c) what kind of operation the
row represents.


\*
 
 SIMPLE means there are no subqueries or unions in the whole query.
 


\*
 
 PRIMARY means there are, but this is the outermost SELECT.
 


\*
 
 [DEPENDENT] UNION means this result is UNIONed with the previous result (not
 row; a result might encompass more than one row).
 


\*
 
 UNION RESULT terminates a set of UNIONed results.
 


\*
 
 [DEPENDENT|UNCACHEABLE] SUBQUERY means a new sub-scope is opening.  This is the
 kind of subquery that happens in a WHERE clause, SELECT list or whatnot; it does
 not return a so-called "derived table."
 


\*
 
 DERIVED is a subquery in the FROM clause.
 


Tables that are JOINed all have the same select_type.  For example, if you JOIN
three tables inside a dependent subquery, they'll all say the same thing:
DEPENDENT SUBQUERY.

The table column usually specifies the table name or alias, but may also say
<derivedN> or <unionN,N...N>.  If it says <derivedN>, the row represents an
access to the temporary table that holds the result of the subquery whose id is
N.  If it says <unionN,..N> it's the same thing, but it refers to the results it
UNIONs together.

Finally, order matters.  If a row's id is less than the one before it, I think
that means it is dependent on something other than the one before it.  For
example,


.. code-block:: perl

  explain select
     (select 1 from sakila.film),
     (select 2 from sakila.film_actor),
     (select 3 from sakila.actor);
 
  | id | select_type | table      |
  +----+-------------+------------+
  |  1 | PRIMARY     | NULL       |
  |  4 | SUBQUERY    | actor      |
  |  3 | SUBQUERY    | film_actor |
  |  2 | SUBQUERY    | film       |


If the results were in order 2-3-4, I think that would mean 3 is a subquery of
2, 4 is a subquery of 3.  As it is, this means 4 is a subquery of the nearest
previous recent row with a smaller id, which is 1.  Likewise for 3 and 2.

This structure is hard to programatically build into a tree for the same reason
it's hard to understand by inspection: there are both forward and backward
references.  <derivedN> is a forward reference to selectN, while <unionM,N> is a
backward reference to selectM and selectN.  That makes recursion and other
tree-building algorithms hard to get right (NOTE: after implementation, I now
see how it would be possible to deal with both forward and backward references,
but I have no motivation to change something that works).  Consider the
following:


.. code-block:: perl

  select * from (
     select 1 from sakila.actor as actor_1
     union
     select 1 from sakila.actor as actor_2
  ) as der_1
  union
  select * from (
     select 1 from sakila.actor as actor_3
     union all
     select 1 from sakila.actor as actor_4
  ) as der_2;
 
  | id   | select_type  | table      |
  +------+--------------+------------+
  |  1   | PRIMARY      | <derived2> |
  |  2   | DERIVED      | actor_1    |
  |  3   | UNION        | actor_2    |
  | NULL | UNION RESULT | <union2,3> |
  |  4   | UNION        | <derived5> |
  |  5   | DERIVED      | actor_3    |
  |  6   | UNION        | actor_4    |
  | NULL | UNION RESULT | <union5,6> |
  | NULL | UNION RESULT | <union1,4> |


This would be a lot easier to work with if it looked like this (I've
bracketed the id on rows I moved):


.. code-block:: perl

  | id   | select_type  | table      |
  +------+--------------+------------+
  | [1]  | UNION RESULT | <union1,4> |
  |  1   | PRIMARY      | <derived2> |
  | [2]  | UNION RESULT | <union2,3> |
  |  2   | DERIVED      | actor_1    |
  |  3   | UNION        | actor_2    |
  |  4   | UNION        | <derived5> |
  | [5]  | UNION RESULT | <union5,6> |
  |  5   | DERIVED      | actor_3    |
  |  6   | UNION        | actor_4    |


In fact, why not re-number all the ids, so the PRIMARY row becomes 2, and so on?
That would make it even easier to read.  Unfortunately that would also have the
effect of destroying the meaning of the id column, which I think is important to
preserve in the final tree.  Also, though it makes it easier to read, it doesn't
make it easier to manipulate programmatically; so it's fine to leave them
numbered as they are.

The goal of re-ordering is to make it easier to figure out which rows are
children of which rows in the execution plan.  Given the reordered list and some
row whose table is <union...> or <derived>, it is easy to find the beginning of
the slice of rows that should be child nodes in the tree: you just look for the
first row whose ID is the same as the first number in the table.

The next question is how to find the last row that should be a child node of a
UNION or DERIVED.   I'll start with DERIVED, because the solution makes UNION
easy.

Consider how MySQL numbers the SELECTs sequentially according to their position
in the SQL, left-to-right.  Since a DERIVED table encloses everything within it
in a scope, which becomes a temporary table, there are only two things to think
about: its child subqueries and unions (if any), and its next siblings in the
scope that encloses it.  Its children will all have an id greater than it does,
by definition, so any later rows with a smaller id terminate the scope.

Here's an example.  The middle derived table here has a subquery and a UNION to
make it a little more complex for the example.


.. code-block:: perl

  explain select 1
  from (
     select film_id from sakila.film limit 1
  ) as der_1
  join (
     select film_id, actor_id, (select count(*) from sakila.rental) as r
     from sakila.film_actor limit 1
     union all
     select 1, 1, 1 from sakila.film_actor as dummy
  ) as der_2 using (film_id)
  join (
     select actor_id from sakila.actor limit 1
  ) as der_3 using (actor_id);


Here's the output of EXPLAIN:


.. code-block:: perl

  | id   | select_type  | table      |
  |  1   | PRIMARY      | <derived2> |
  |  1   | PRIMARY      | <derived6> |
  |  1   | PRIMARY      | <derived3> |
  |  6   | DERIVED      | actor      |
  |  3   | DERIVED      | film_actor |
  |  4   | SUBQUERY     | rental     |
  |  5   | UNION        | dummy      |
  | NULL | UNION RESULT | <union3,5> |
  |  2   | DERIVED      | film       |


The siblings all have id 1, and the middle one I care about is derived3.
(Notice MySQL doesn't execute them in the order I defined them, which is fine).
Now notice that MySQL prints out the rows in the opposite order I defined the
subqueries: 6, 3, 2.  It always seems to do this, and there might be other
methods of finding the scope boundaries including looking for the lower boundary
of the next largest sibling, but this is a good enough heuristic.  I am forced
to rely on it for non-DERIVED subqueries, so I rely on it here too.  Therefore,
I decide that everything greater than or equal to 3 belongs to the DERIVED
scope.

The rule for UNION is simple: they consume the entire enclosing scope, and to
find the component parts of each one, you find each part's beginning as referred
to in the <unionN,...> definition, and its end is either just before the next
one, or if it's the last part, the end is the end of the scope.

This is only simple because UNION consumes the entire scope, which is either the
entire statement, or the scope of a DERIVED table.  This is because a UNION
cannot be a sibling of another UNION or a table, DERIVED or not.  (Try writing
such a statement if you don't see it intuitively).  Therefore, you can just find
the enclosing scope's boundaries, and the rest is easy.  Notice in the example
above, the UNION is over <union3,5>, which includes the row with id 4 -- it
includes every row between 3 and 5.

Finally, there are non-derived subqueries to deal with as well.  In this case I
can't look at siblings to find the end of the scope as I did for DERIVED.  I
have to trust that MySQL executes depth-first.  Here's an example:


.. code-block:: perl

  explain
  select actor_id,
  (
     select count(film_id)
     + (select count(*) from sakila.film)
     from sakila.film join sakila.film_actor using(film_id)
     where exists(
        select * from sakila.actor
        where sakila.actor.actor_id = sakila.film_actor.actor_id
     )
  )
  from sakila.actor;
 
  | id | select_type        | table      |
  |  1 | PRIMARY            | actor      |
  |  2 | SUBQUERY           | film       |
  |  2 | SUBQUERY           | film_actor |
  |  4 | DEPENDENT SUBQUERY | actor      |
  |  3 | SUBQUERY           | film       |


In order, the tree should be built like this:


\*
 
 See row 1.
 


\*
 
 See row 2.  It's a higher id than 1, so it's a subquery, along with every other
 row whose id is greater than 2.
 


\*
 
 Inside this scope, see 2 and 2 and JOIN them.  See 4.  It's a higher id than 2,
 so it's again a subquery; recurse.  After that, see 3, which is also higher;
 recurse.
 


But the only reason the nested subquery didn't include select 3 is because
select 4 came first.  In other words, if EXPLAIN looked like this,


.. code-block:: perl

  | id | select_type        | table      |
  |  1 | PRIMARY            | actor      |
  |  2 | SUBQUERY           | film       |
  |  2 | SUBQUERY           | film_actor |
  |  3 | SUBQUERY           | film       |
  |  4 | DEPENDENT SUBQUERY | actor      |


I would be forced to assume upon seeing select 3 that select 4 is a subquery
of it, rather than just being the next sibling in the enclosing scope.  If this
is ever wrong, then the algorithm is wrong, and I don't see what could be done
about it.

UNION is a little more complicated than just "the entire scope is a UNION,"
because the UNION might itself be inside an enclosing scope that's only
indicated by the first item inside the UNION.  There are only three kinds of
enclosing scopes: UNION, DERIVED, and SUBQUERY.  A UNION can't enclose a UNION,
and a DERIVED has its own "scope markers," but a SUBQUERY can wholly enclose a
UNION, like this strange example on the empty table t1:


.. code-block:: perl

  explain select * from t1 where not exists(
     (select t11.i from t1 t11) union (select t12.i from t1 t12));
 
  |   id | select_type  | table      | Extra                          |
  +------+--------------+------------+--------------------------------+
  |    1 | PRIMARY      | t1         | const row not found            |
  |    2 | SUBQUERY     | NULL       | No tables used                 |
  |    3 | SUBQUERY     | NULL       | no matching row in const table |
  |    4 | UNION        | t12        | const row not found            |
  | NULL | UNION RESULT | <union2,4> |                                |


The UNION's backward references might make it look like the UNION encloses the
subquery, but studying the query makes it clear this isn't the case.  So when a
UNION's first row says SUBQUERY, it is this special case.

By the way, I don't fully understand this query plan; there are 4 numbered
SELECT in the plan, but only 3 in the query.  The parens around the UNIONs are
meaningful.  Removing them will make the EXPLAIN different.  Please tell me how
and why this works if you know.

Armed with this knowledge, it's possible to use recursion to turn the
parent-child relationship between all the rows into a tree representing the
execution plan.

MySQL prints the rows in execution order, even the forward and backward
references.  At any given scope, the rows are processed as a left-deep tree.
MySQL does not do "bushy" execution plans.  It begins with a table, finds a
matching row in the next table, and continues till the last table, when it emits
a row.  When it runs out, it backtracks till it can find the next row and
repeats.  There are subtleties of course, but this is the basic plan.  This is
why MySQL transforms all RIGHT OUTER JOINs into LEFT OUTER JOINs and cannot do
FULL OUTER JOIN.

This means in any given scope, say


.. code-block:: perl

  | id   | select_type  | table      |
  |  1   | SIMPLE       | tbl1       |
  |  1   | SIMPLE       | tbl2       |
  |  1   | SIMPLE       | tbl3       |


The execution plan looks like a depth-first traversal of this tree:


.. code-block:: perl

        JOIN
       /    \
     JOIN  tbl3
    /    \
  tbl1   tbl2


The JOIN might not be a JOIN.  It might be a subquery, for example.  This comes
from the type column of EXPLAIN.  The documentation says this is a "join type,"
but I think "access type" is more accurate, because it's "how MySQL accesses
rows."

pt-visual-explain decorates the tree significantly more than just turning
rows into nodes.  Each node may get a series of transformations that turn it
into a subtree of more than one node.  For example, an index scan not marked
with 'Using index' must do a bookmark lookup into the table rows; that is a
three-node subtree.  However, after the above node-ordering and scoping stuff,
the rest of the process is pretty simple.


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
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
 runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
 binmode on STDOUT without the utf8 layer, and runs SET NAMES after
 connecting to MySQL.
 


--clustered-pk
 
 Assume that PRIMARY KEY index accesses don't need to do a bookmark lookup to
 retrieve rows.  This is the case for InnoDB.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--connect
 
 Treat input as a query, and obtain EXPLAIN output by connecting to a MySQL
 instance and running EXPLAIN on the query.  When this option is given,
 pt-visual-explain uses the other connection-specific options such as
 "--user" to connect to the MySQL instance.  If you have a .my.cnf file,
 it will read it, so you may not need to specify any connection-specific
 options.
 


--database
 
 short form: -D; type: string
 
 Connect to this database.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--format
 
 type: string; default: tree
 
 Set output format.
 
 The default is a terse pretty-printed tree. The valid values are:
 
 
 .. code-block:: perl
 
   Value  Meaning
   =====  ================================================
   tree   Pretty-printed terse tree.
   dump   Data::Dumper output (see Data::Dumper for more).
 
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


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
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this
 string will be appended to SET and executed.
 


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
 


\* u
 
 dsn: user; copy: yes
 
 User for login if not current user.
 



***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-visual-explain ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-visual-explain <http://www.percona.com/bugs/pt-visual-explain>`_.

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

