
###############
pt-query-digest
###############

.. highlight:: perl


****
NAME
****


pt-query-digest - Analyze query execution logs and generate a query report, filter, replay, or transform queries for MySQL, PostgreSQL, memcached, and more.


********
SYNOPSIS
********


Usage: pt-query-digest [OPTION...] [FILE]

pt-query-digest parses and analyzes MySQL log files.  With no FILE, or when
FILE is -, it read standard input.

Analyze, aggregate, and report on a slow query log:


.. code-block:: perl

  pt-query-digest /path/to/slow.log


Review a slow log, saving results to the test.query_review table in a MySQL
server running on host1.  See "--review" for more on reviewing queries:


.. code-block:: perl

  pt-query-digest --review h=host1,D=test,t=query_review /path/to/slow.log


Filter out everything but SELECT queries, replay the queries against another
server, then use the timings from replaying them to analyze their performance:


.. code-block:: perl

  pt-query-digest /path/to/slow.log --execute h=another_server \
    --filter '$event->{fingerprint} =~ m/^select/'


Print the structure of events so you can construct a complex "--filter":


.. code-block:: perl

  pt-query-digest /path/to/slow.log --no-report \
    --filter 'print Dumper($event)'


Watch SHOW FULL PROCESSLIST and output a log in slow query log format:


.. code-block:: perl

  pt-query-digest --processlist h=host1 --print --no-report


The default aggregation and analysis is CPU and memory intensive.  Disable it if
you don't need the default report:


.. code-block:: perl

  pt-query-digest <arguments> --no-report



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

By default pt-query-digest merely collects and aggregates data from the files
specified.  It is designed to be as efficient as possible, but depending on the
input you give it, it can use a lot of CPU and memory.  Practically speaking, it
is safe to run even on production systems, but you might want to monitor it
until you are satisfied that the input you give it does not cause undue load.

Various options will cause pt-query-digest to insert data into tables, execute
SQL queries, and so on.  These include the "--execute" option and
"--review".

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-query-digest <http://www.percona.com/bugs/pt-query-digest>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


\ ``pt-query-digest``\  is a framework for doing things with events from a query
source such as the slow query log or PROCESSLIST.  By default it acts as a very
sophisticated log analysis tool.  You can group and sort queries in many
different ways simultaneously and find the most expensive queries, or create a
timeline of queries in the log, for example.  It can also do a "query review,"
which means to save a sample of each type of query into a MySQL table so you can
easily see whether you've reviewed and analyzed a query before.  The benefit of
this is that you can keep track of changes to your server's queries and avoid
repeated work.  You can also save other information with the queries, such as
comments, issue numbers in your ticketing system, and so on.

Note that this is a work in \*very\* active progress and you should expect
incompatible changes in the future.


**********
ATTRIBUTES
**********


pt-query-digest works on events, which are a collection of key/value pairs
called attributes.  You'll recognize most of the attributes right away:
Query_time, Lock_time, and so on.  You can just look at a slow log and see them.
However, there are some that don't exist in the slow log, and slow logs
may actually include different kinds of attributes (for example, you may have a
server with the Percona patches).

For a full list of attributes, see
`http://code.google.com/p/maatkit/wiki/EventAttributes <http://code.google.com/p/maatkit/wiki/EventAttributes>`_.

With creative use of "--filter", you can create new attributes derived
from existing attributes.  For example, to create an attribute called
\ ``Row_ratio``\  for examining the ratio of \ ``Rows_sent``\  to \ ``Rows_examined``\ ,
specify a filter like:


.. code-block:: perl

   --filter '($event->{Row_ratio} = $event->{Rows_sent} / ($event->{Rows_examined})) && 1'


The \ ``&& 1``\  trick is needed to create a valid one-line syntax that is always
true, even if the assignment happens to evaluate false.  The new attribute will
automatically appears in the output:


.. code-block:: perl

   # Row ratio           1.00    0.00       1    0.50       1    0.71    0.50


Attributes created this way can be specified for "--order-by" or any
option that requires an attribute.

memcached
=========


memcached events have additional attributes related to the memcached protocol:
cmd, key, res (result) and val.  Also, boolean attributes are created for
the various commands, misses and errors: Memc_CMD where CMD is a memcached
command (get, set, delete, etc.), Memc_error and Memc_miss.

These attributes are no different from slow log attributes, so you can use them
with "--[no]report", "--group-by", in a "--filter", etc.

These attributes and more are documented at
`http://code.google.com/p/maatkit/wiki/EventAttributes <http://code.google.com/p/maatkit/wiki/EventAttributes>`_.



******
OUTPUT
******


The default output is a query analysis report.  The "--[no]report" option
controls whether or not this report is printed.  Sometimes you may wish to
parse all the queries but suppress the report, for example when using
"--print" or "--review".

There is one paragraph for each class of query analyzed.  A "class" of queries
all have the same value for the "--group-by" attribute which is
"fingerprint" by default.  (See "ATTRIBUTES".)  A fingerprint is an
abstracted version of the query text with literals removed, whitespace
collapsed, and so forth.  The report is formatted so it's easy to paste into
emails without wrapping, and all non-query lines begin with a comment, so you
can save it to a .sql file and open it in your favorite syntax-highlighting
text editor.  There is a response-time profile at the beginning.

The output described here is controlled by "--report-format".
That option allows you to specify what to print and in what order.
The default output in the default order is described here.

The report, by default, begins with a paragraph about the entire analysis run
The information is very similar to what you'll see for each class of queries in
the log, but it doesn't have some information that would be too expensive to
keep globally for the analysis.  It also has some statistics about the code's
execution itself, such as the CPU and memory usage, the local date and time
of the run, and a list of input file read/parsed.

Following this is the response-time profile over the events.  This is a
highly summarized view of the unique events in the detailed query report
that follows.  It contains the following columns:


.. code-block:: perl

  Column        Meaning
  ============  ==========================================================
  Rank          The query's rank within the entire set of queries analyzed
  Query ID      The query's fingerprint
  Response time The total response time, and percentage of overall total
  Calls         The number of times this query was executed
  R/Call        The mean response time per execution
  Apdx          The Apdex score; see --apdex-threshold for details
  V/M           The Variance-to-mean ratio of response time
  EXPLAIN       If --explain was specified, a sparkline; see --explain
  Item          The distilled query


A final line whose rank is shown as MISC contains aggregate statistics on the
queries that were not included in the report, due to options such as
"--limit" and "--outliers".  For details on the variance-to-mean ratio,
please see http://en.wikipedia.org/wiki/Index_of_dispersion.

Next, the detailed query report is printed.  Each query appears in a paragraph.
Here is a sample, slightly reformatted so 'perldoc' will not wrap lines in a
terminal.  The following will all be one paragraph, but we'll break it up for
commentary.


.. code-block:: perl

  # Query 2: 0.01 QPS, 0.02x conc, ID 0xFDEA8D2993C9CAF3 at byte 160665


This line identifies the sequential number of the query in the sort order
specified by "--order-by".  Then there's the queries per second, and the
approximate concurrency for this query (calculated as a function of the timespan
and total Query_time).  Next there's a query ID.  This ID is a hex version of
the query's checksum in the database, if you're using "--review".  You can
select the reviewed query's details from the database with a query like \ ``SELECT
.... WHERE checksum=0xFDEA8D2993C9CAF3``\ .

If you are investigating the report and want to print out every sample of a
particular query, then the following "--filter" may be helpful:
\ ``pt-query-digest slow-log.log --no-report --print --filter '$event-``\ {fingerprint} 
&& make_checksum($event->{fingerprint}) eq "FDEA8D2993C9CAF3"'>.

Notice that you must remove the 0x prefix from the checksum in order for this to work.

Finally, in case you want to find a sample of the query in the log file, there's
the byte offset where you can look.  (This is not always accurate, due to some
silly anomalies in the slow-log format, but it's usually right.)  The position
refers to the worst sample, which we'll see more about below.

Next is the table of metrics about this class of queries.


.. code-block:: perl

  #           pct   total    min    max     avg     95%  stddev  median
  # Count       0       2
  # Exec time  13   1105s   552s   554s    553s    554s      2s    553s
  # Lock time   0   216us   99us  117us   108us   117us    12us   108us
  # Rows sent  20   6.26M  3.13M  3.13M   3.13M   3.13M   12.73   3.13M
  # Rows exam   0   6.26M  3.13M  3.13M   3.13M   3.13M   12.73   3.13M


The first line is column headers for the table.  The percentage is the percent
of the total for the whole analysis run, and the total is the actual value of
the specified metric.  For example, in this case we can see that the query
executed 2 times, which is 13% of the total number of queries in the file.  The
min, max and avg columns are self-explanatory.  The 95% column shows the 95th
percentile; 95% of the values are less than or equal to this value.  The
standard deviation shows you how tightly grouped the values are.  The standard
deviation and median are both calculated from the 95th percentile, discarding
the extremely large values.

The stddev, median and 95th percentile statistics are approximate.  Exact
statistics require keeping every value seen, sorting, and doing some
calculations on them.  This uses a lot of memory.  To avoid this, we keep 1000
buckets, each of them 5% bigger than the one before, ranging from .000001 up to
a very big number.  When we see a value we increment the bucket into which it
falls.  Thus we have fixed memory per class of queries.  The drawback is the
imprecision, which typically falls in the 5 percent range.

Next we have statistics on the users, databases and time range for the query.


.. code-block:: perl

  # Users       1   user1
  # Databases   2     db1(1), db2(1)
  # Time range 2008-11-26 04:55:18 to 2008-11-27 00:15:15


The users and databases are shown as a count of distinct values, followed by the
values.  If there's only one, it's shown alone; if there are many, we show each
of the most frequent ones, followed by the number of times it appears.


.. code-block:: perl

  # Query_time distribution
  #   1us
  #  10us
  # 100us
  #   1ms
  #  10ms
  # 100ms
  #    1s
  #  10s+  #############################################################


The execution times show a logarithmic chart of time clustering.  Each query
goes into one of the "buckets" and is counted up.  The buckets are powers of
ten.  The first bucket is all values in the "single microsecond range" -- that
is, less than 10us.  The second is "tens of microseconds," which is from 10us
up to (but not including) 100us; and so on.  The charted attribute can be
changed by specifying "--report-histogram" but is limited to time-based
attributes.


.. code-block:: perl

  # Tables
  #    SHOW TABLE STATUS LIKE 'table1'\G
  #    SHOW CREATE TABLE `table1`\G
  # EXPLAIN
  SELECT * FROM table1\G


This section is a convenience: if you're trying to optimize the queries you see
in the slow log, you probably want to examine the table structure and size.
These are copy-and-paste-ready commands to do that.

Finally, we see a sample of the queries in this class of query.  This is not a
random sample.  It is the query that performed the worst, according to the sort
order given by "--order-by".  You will normally see a commented \ ``# EXPLAIN``\ 
line just before it, so you can copy-paste the query to examine its EXPLAIN
plan. But for non-SELECT queries that isn't possible to do, so the tool tries to
transform the query into a roughly equivalent SELECT query, and adds that below.

If you want to find this sample event in the log, use the offset mentioned
above, and something like the following:


.. code-block:: perl

   tail -c +<offset> /path/to/file | head


See also "--report-format".

SPARKLINES
==========


The output also contains sparklines.  Sparklines are "data-intense,
design-simple, word-sized graphics" (`http://en.wikipedia.org/wiki/Sparkline <http://en.wikipedia.org/wiki/Sparkline>`_).There is a sparkline for "--report-histogram" and for "--explain".
See each of those options for details about interpreting their sparklines.



*************
QUERY REVIEWS
*************


A "query review" is the process of storing all the query fingerprints analyzed.
This has several benefits:


\*
 
 You can add meta-data to classes of queries, such as marking them for follow-up,
 adding notes to queries, or marking them with an issue ID for your issue
 tracking system.
 


\*
 
 You can refer to the stored values on subsequent runs so you'll know whether
 you've seen a query before.  This can help you cut down on duplicated work.
 


\*
 
 You can store historical data such as the row count, query times, and generally
 anything you can see in the report.
 


To use this feature, you run pt-query-digest with the "--review" option.  It
will store the fingerprints and other information into the table you specify.
Next time you run it with the same option, it will do the following:


\*
 
 It won't show you queries you've already reviewed.  A query is considered to be
 already reviewed if you've set a value for the \ ``reviewed_by``\  column.  (If you
 want to see queries you've already reviewed, use the "--report-all" option.)
 


\*
 
 Queries that you've reviewed, and don't appear in the output, will cause gaps in
 the query number sequence in the first line of each paragraph.  And the value
 you've specified for "--limit" will still be honored.  So if you've reviewed all
 queries in the top 10 and you ask for the top 10, you won't see anything in the
 output.
 


\*
 
 If you want to see the queries you've already reviewed, you can specify
 "--report-all".  Then you'll see the normal analysis output, but you'll also see
 the information from the review table, just below the execution time graph.  For
 example,
 
 
 .. code-block:: perl
 
    # Review information
    #      comments: really bad IN() subquery, fix soon!
    #    first_seen: 2008-12-01 11:48:57
    #   jira_ticket: 1933
    #     last_seen: 2008-12-18 11:49:07
    #      priority: high
    #   reviewed_by: xaprb
    #   reviewed_on: 2008-12-18 15:03:11
 
 
 You can see how useful this meta-data is -- as you analyze your queries, you get
 your comments integrated right into the report.
 
 If you add the "--review-history" option, it will also store information into
 a separate database table, so you can keep historical trending information on
 classes of queries.
 



************
FINGERPRINTS
************


A query fingerprint is the abstracted form of a query, which makes it possible
to group similar queries together.  Abstracting a query removes literal values,
normalizes whitespace, and so on.  For example, consider these two queries:


.. code-block:: perl

   SELECT name, password FROM user WHERE id='12823';
   select name,   password from user
      where id=5;


Both of those queries will fingerprint to


.. code-block:: perl

   select name, password from user where id=?


Once the query's fingerprint is known, we can then talk about a query as though
it represents all similar queries.

What \ ``pt-query-digest``\  does is analogous to a GROUP BY statement in SQL.  (But
note that "multiple columns" doesn't define a multi-column grouping; it defines
multiple reports!) If your command-line looks like this,


.. code-block:: perl

   pt-query-digest /path/to/slow.log --select Rows_read,Rows_sent \
       --group-by fingerprint --order-by Query_time:sum --limit 10


The corresponding pseudo-SQL looks like this:


.. code-block:: perl

   SELECT WORST(query BY Query_time), SUM(Query_time), ...
   FROM /path/to/slow.log
   GROUP BY FINGERPRINT(query)
   ORDER BY SUM(Query_time) DESC
   LIMIT 10


You can also use the value \ ``distill``\ , which is a kind of super-fingerprint.
See "--group-by" for more.

When parsing memcached input ("--type" memcached), the fingerprint is an
abstracted version of the command and key, with placeholders removed.  For
example, \ ``get user_123_preferences``\  fingerprints to \ ``get user_?_preferences``\ .
There is also a \ ``key_print``\  which a fingerprinted version of the key.  This
example's key_print is \ ``user_?_preferences``\ .

Query fingerprinting accommodates a great many special cases, which have proven
necessary in the real world.  For example, an IN list with 5 literals is really
equivalent to one with 4 literals, so lists of literals are collapsed to a
single one.  If you want to understand more about how and why all of these cases
are handled, please review the test cases in the Subversion repository.  If you
find something that is not fingerprinted properly, please submit a bug report
with a reproducible test case.  Here is a list of transformations during
fingerprinting, which might not be exhaustive:


\*
 
 Group all SELECT queries from mysqldump together, even if they are against
 different tables.  Ditto for all of pt-table-checksum's checksum queries.
 


\*
 
 Shorten multi-value INSERT statements to a single VALUES() list.
 


\*
 
 Strip comments.
 


\*
 
 Abstract the databases in USE statements, so all USE statements are grouped
 together.
 


\*
 
 Replace all literals, such as quoted strings.  For efficiency, the code that
 replaces literal numbers is somewhat non-selective, and might replace some
 things as numbers when they really are not.  Hexadecimal literals are also
 replaced.  NULL is treated as a literal.  Numbers embedded in identifiers are
 also replaced, so tables named similarly will be fingerprinted to the same
 values (e.g. users_2009 and users_2010 will fingerprint identically).
 


\*
 
 Collapse all whitespace into a single space.
 


\*
 
 Lowercase the entire query.
 


\*
 
 Replace all literals inside of IN() and VALUES() lists with a single
 placeholder, regardless of cardinality.
 


\*
 
 Collapse multiple identical UNION queries into a single one.
 



*******
OPTIONS
*******


DSN values in "--review-history" default to values in "--review" if COPY
is yes.

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--apdex-threshold
 
 type: float; default: 1.0
 
 Set Apdex target threshold (T) for query response time.  The Application
 Performance Index (Apdex) Technical Specification V1.1 defines T as "a
 positive decimal value in seconds, having no more than two significant digits
 of granularity."  This value only applies to query response time (Query_time).
 
 Options can be abbreviated so specifying \ ``--apdex-t``\  also works.
 
 See `http://www.apdex.org/ <http://www.apdex.org/>`_.
 


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--attribute-aliases
 
 type: array; default: db|Schema
 
 List of attribute|alias,etc.
 
 Certain attributes have multiple names, like db and Schema.  If an event does
 not have the primary attribute, pt-query-digest looks for an alias attribute.
 If it finds an alias, it creates the primary attribute with the alias
 attribute's value and removes the alias attribute.
 
 If the event has the primary attribute, all alias attributes are deleted.
 
 This helps simplify event attributes so that, for example, there will not
 be report lines for both db and Schema.
 


--attribute-value-limit
 
 type: int; default: 4294967296
 
 A sanity limit for attribute values.
 
 This option deals with bugs in slow-logging functionality that causes large
 values for attributes.  If the attribute's value is bigger than this, the
 last-seen value for that class of query is used instead.
 


--aux-dsn
 
 type: DSN
 
 Auxiliary DSN used for special options.
 
 The following options may require a DSN even when only parsing a slow log file:
 
 
 .. code-block:: perl
 
    * --since
    * --until
 
 
 See each option for why it might require a DSN.
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
 runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
 binmode on STDOUT without the utf8 layer, and runs SET NAMES after
 connecting to MySQL.
 


--check-attributes-limit
 
 type: int; default: 1000
 
 Stop checking for new attributes after this many events.
 
 For better speed, pt-query-digest stops checking events for new attributes
 after a certain number of events.  Any new attributes after this number
 will be ignored and will not be reported.
 
 One special case is new attributes for pre-existing query classes
 (see "--group-by" about query classes).  New attributes will not be added
 to pre-existing query classes even if the attributes are detected before the
 "--check-attributes-limit" limit.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--[no]continue-on-error
 
 default: yes
 
 Continue parsing even if there is an error.
 


--create-review-history-table
 
 Create the "--review-history" table if it does not exist.
 
 This option causes the table specified by "--review-history" to be created
 with the default structure shown in the documentation for that option.
 


--create-review-table
 
 Create the "--review" table if it does not exist.
 
 This option causes the table specified by "--review" to be created with the
 default structure shown in the documentation for that option.
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX
 operating systems only.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute pathname.
 


--embedded-attributes
 
 type: array
 
 Two Perl regex patterns to capture pseudo-attributes embedded in queries.
 
 Embedded attributes might be special attribute-value pairs that you've hidden
 in comments.  The first regex should match the entire set of attributes (in
 case there are multiple).  The second regex should match and capture
 attribute-value pairs from the first regex.
 
 For example, suppose your query looks like the following:
 
 
 .. code-block:: perl
 
    SELECT * from users -- file: /login.php, line: 493;
 
 
 You might run pt-query-digest with the following option:
 
 
 .. code-block:: perl
 
    pt-query-digest --embedded-attributes ' -- .*','(\w+): ([^\,]+)'
 
 
 The first regular expression captures the whole comment:
 
 
 .. code-block:: perl
 
    " -- file: /login.php, line: 493;"
 
 
 The second one splits it into attribute-value pairs and adds them to the event:
 
 
 .. code-block:: perl
 
     ATTRIBUTE  VALUE
     =========  ==========
     file       /login.php
     line       493
 
 
 \ **NOTE**\ : All commas in the regex patterns must be escaped with \ otherwise
 the pattern will break.
 


--execute
 
 type: DSN
 
 Execute queries on this DSN.
 
 Adds a callback into the chain, after filters but before the reports.  Events
 are executed on this DSN.  If they are successful, the time they take to execute
 overwrites the event's Query_time attribute and the original Query_time value
 (from the log) is saved as the Exec_orig_time attribute.  If unsuccessful,
 the callback returns false and terminates the chain.
 
 If the connection fails, pt-query-digest tries to reconnect once per second.
 
 See also "--mirror" and "--execute-throttle".
 


--execute-throttle
 
 type: array
 
 Throttle values for "--execute".
 
 By default "--execute" runs without any limitations or concerns for the
 amount of time that it takes to execute the events.  The "--execute-throttle"
 allows you to limit the amount of time spent doing "--execute" relative
 to the other processes that handle events.  This works by marking some events
 with a \ ``Skip_exec``\  attribute when "--execute" begins to take too much time.
 "--execute" will not execute an event if this attribute is true.  This
 indirectly decreases the time spent doing "--execute".
 
 The "--execute-throttle" option takes at least two comma-separated values:
 max allowed "--execute" time as a percentage and a check interval time.  An
 optional third value is a percentage step for increasing and decreasing the
 probability that an event will be marked \ ``Skip_exec``\  true.  5 (percent) is
 the default step.
 
 For example: "--execute-throttle" \ ``70,60,10``\ .  This will limit
 "--execute" to 70% of total event processing time, checked every minute
 (60 seconds) and probability stepped up and down by 10%.  When "--execute"
 exceeds 70%, the probability that events will be marked \ ``Skip_exec``\  true
 increases by 10%. "--execute" time is checked again after another minute.
 If it's still above 70%, then the probability will increase another 10%.
 Or, if it's dropped below 70%, then the probability will decrease by 10%.
 


--expected-range
 
 type: array; default: 5,10
 
 Explain items when there are more or fewer than expected.
 
 Defines the number of items expected to be seen in the report given by
 "--[no]report", as controlled by "--limit" and "--outliers".  If
 there  are more or fewer items in the report, each one will explain why it was
 included.
 


--explain
 
 type: DSN
 
 Run EXPLAIN for the sample query with this DSN and print results.
 
 This works only when "--group-by" includes fingerprint.  It causes
 pt-query-digest to run EXPLAIN and include the output into the report.  For
 safety, queries that appear to have a subquery that EXPLAIN will execute won't
 be EXPLAINed.  Those are typically "derived table" queries of the form
 
 
 .. code-block:: perl
 
    select ... from ( select .... ) der;
 
 
 The EXPLAIN results are printed in three places: a sparkline in the event
 header, a full vertical format in the event report, and a sparkline in the
 profile.
 
 The full format appears at the end of each event report in vertical style
 (\ ``\G``\ ) just like MySQL prints it.
 
 The sparklines (see "SPARKLINES") are compact representations of the
 access type for each table and whether or not "Using temporary" or "Using
 filesort" appear in EXPLAIN.  The sparklines look like:
 
 
 .. code-block:: perl
 
    nr>TF
 
 
 That sparkline means that there are two tables, the first uses a range (n)
 access, the second uses a ref access, and both "Using temporary" (T) and
 "Using filesort" (F) appear.  The greater-than character just separates table
 access codes from T and/or F.
 
 The abbreviated table access codes are:
 
 
 .. code-block:: perl
 
    a  ALL
    c  const
    e  eq_ref
    f  fulltext
    i  index
    m  index_merge
    n  range
    o  ref_or_null
    r  ref
    s  system
    u  unique_subquery
 
 
 A capitalized access code means that "Using index" appears in EXPLAIN for
 that table.
 


--filter
 
 type: string
 
 Discard events for which this Perl code doesn't return true.
 
 This option is a string of Perl code or a file containing Perl code that gets
 compiled into a subroutine with one argument: $event.  This is a hashref.
 If the given value is a readable file, then pt-query-digest reads the entire
 file and uses its contents as the code.  The file should not contain
 a shebang (#!/usr/bin/perl) line.
 
 If the code returns true, the chain of callbacks continues; otherwise it ends.
 The code is the last statement in the subroutine other than \ ``return $event``\ . 
 The subroutine template is:
 
 
 .. code-block:: perl
 
    sub { $event = shift; filter && return $event; }
 
 
 Filters given on the command line are wrapped inside parentheses like like
 \ ``( filter )``\ .  For complex, multi-line filters, you must put the code inside
 a file so it will not be wrapped inside parentheses.  Either way, the filter
 must produce syntactically valid code given the template.  For example, an
 if-else branch given on the command line would not be valid:
 
 
 .. code-block:: perl
 
    --filter 'if () { } else { }'  # WRONG
 
 
 Since it's given on the command line, the if-else branch would be wrapped inside
 parentheses which is not syntactically valid.  So to accomplish something more
 complex like this would require putting the code in a file, for example
 filter.txt:
 
 
 .. code-block:: perl
 
    my $event_ok; if (...) { $event_ok=1; } else { $event_ok=0; } $event_ok
 
 
 Then specify \ ``--filter filter.txt``\  to read the code from filter.txt.
 
 If the filter code won't compile, pt-query-digest will die with an error.
 If the filter code does compile, an error may still occur at runtime if the
 code tries to do something wrong (like pattern match an undefined value).
 pt-query-digest does not provide any safeguards so code carefully!
 
 An example filter that discards everything but SELECT statements:
 
 
 .. code-block:: perl
 
    --filter '$event->{arg} =~ m/^select/i'
 
 
 This is compiled into a subroutine like the following:
 
 
 .. code-block:: perl
 
    sub { $event = shift; ( $event->{arg} =~ m/^select/i ) && return $event; }
 
 
 It is permissible for the code to have side effects (to alter \ ``$event``\ ).
 
 You can find an explanation of the structure of $event at
 `http://code.google.com/p/maatkit/wiki/EventAttributes <http://code.google.com/p/maatkit/wiki/EventAttributes>`_.
 
 Here are more examples of filter code:
 
 
 Host/IP matches domain.com
  
  --filter '($event->{host} || $event->{ip} || "") =~ m/domain.com/'
  
  Sometimes MySQL logs the host where the IP is expected.  Therefore, we
  check both.
  
 
 
 User matches john
  
  --filter '($event->{user} || "") =~ m/john/'
  
 
 
 More than 1 warning
  
  --filter '($event->{Warning_count} || 0) > 1'
  
 
 
 Query does full table scan or full join
  
  --filter '(($event->{Full_scan} || "") eq "Yes") || (($event->{Full_join} || "") eq "Yes")'
  
 
 
 Query was not served from query cache
  
  --filter '($event->{QC_Hit} || "") eq "No"'
  
 
 
 Query is 1 MB or larger
  
  --filter '$event->{bytes} >= 1_048_576'
  
 
 
 Since "--filter" allows you to alter \ ``$event``\ , you can use it to do other
 things, like create new attributes.  See "ATTRIBUTES" for an example.
 


--fingerprints
 
 Add query fingerprints to the standard query analysis report.  This is mostly
 useful for debugging purposes.
 


--[no]for-explain
 
 default: yes
 
 Print extra information to make analysis easy.
 
 This option adds code snippets to make it easy to run SHOW CREATE TABLE and SHOW
 TABLE STATUS for the query's tables.  It also rewrites non-SELECT queries into a
 SELECT that might be helpful for determining the non-SELECT statement's index
 usage.
 


--group-by
 
 type: Array; default: fingerprint
 
 Which attribute of the events to group by.
 
 In general, you can group queries into classes based on any attribute of the
 query, such as \ ``user``\  or \ ``db``\ , which will by default show you which users
 and which databases get the most \ ``Query_time``\ .  The default attribute,
 \ ``fingerprint``\ , groups similar, abstracted queries into classes; see below
 and see also "FINGERPRINTS".
 
 A report is printed for each "--group-by" value (unless \ ``--no-report``\  is
 given).  Therefore, \ ``--group-by user,db``\  means "report on queries with the
 same user and report on queries with the same db"--it does not mean "report
 on queries with the same user and db."  See also "OUTPUT".
 
 Every value must have a corresponding value in the same position in
 "--order-by".  However, adding values to "--group-by" will automatically
 add values to "--order-by", for your convenience.
 
 There are several magical values that cause some extra data mining to happen
 before the grouping takes place:
 
 
 fingerprint
  
  This causes events to be fingerprinted to abstract queries into
  a canonical form, which is then used to group events together into a class.
  See "FINGERPRINTS" for more about fingerprinting.
  
 
 
 tables
  
  This causes events to be inspected for what appear to be tables, and
  then aggregated by that.  Note that a query that contains two or more tables
  will be counted as many times as there are tables; so a join against two tables
  will count the Query_time against both tables.
  
 
 
 distill
  
  This is a sort of super-fingerprint that collapses queries down
  into a suggestion of what they do, such as \ ``INSERT SELECT table1 table2``\ .
  
 
 
 If parsing memcached input ("--type" memcached), there are other
 attributes which you can group by: key_print (see memcached section in
 "FINGERPRINTS"), cmd, key, res and val (see memcached section in
 "ATTRIBUTES").
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--ignore-attributes
 
 type: array; default: arg, cmd, insert_id, ip, port, Thread_id, timestamp, exptime, flags, key, res, val, server_id, offset, end_log_pos, Xid
 
 Do not aggregate these attributes when auto-detecting "--select".
 
 If you do not specify "--select" then pt-query-digest auto-detects and
 aggregates every attribute that it finds in the slow log.  Some attributes,
 however, should not be aggregated.  This option allows you to specify a list
 of attributes to ignore.  This only works when no explicit "--select" is
 given.
 


--inherit-attributes
 
 type: array; default: db,ts
 
 If missing, inherit these attributes from the last event that had them.
 
 This option sets which attributes are inherited or carried forward to events
 which do not have them.  For example, if one event has the db attribute equal
 to "foo", but the next event doesn't have the db attribute, then it inherits
 "foo" for its db attribute.
 
 Inheritance is usually desirable, but in some cases it might confuse things.
 If a query inherits a database that it doesn't actually use, then this could
 confuse "--execute".
 


--interval
 
 type: float; default: .1
 
 How frequently to poll the processlist, in seconds.
 


--iterations
 
 type: int; default: 1
 
 How many times to iterate through the collect-and-report cycle.  If 0, iterate
 to infinity.  Each iteration runs for "--run-time" amount of time.  An
 iteration is usually determined by an amount of time and a report is printed
 when that amount of time elapses.  With "--run-time-mode" \ ``interval``\ ,
 an interval is instead determined by the interval time you specify with
 "--run-time".  See "--run-time" and "--run-time-mode" for more
 information.
 


--limit
 
 type: Array; default: 95%:20
 
 Limit output to the given percentage or count.
 
 If the argument is an integer, report only the top N worst queries.  If the
 argument is an integer followed by the \ ``%``\  sign, report that percentage of the
 worst queries.  If the percentage is followed by a colon and another integer,
 report the top percentage or the number specified by that integer, whichever
 comes first.
 
 The value is actually a comma-separated array of values, one for each item in
 "--group-by".  If you don't specify a value for any of those items, the
 default is the top 95%.
 
 See also "--outliers".
 


--log
 
 type: string
 
 Print all output to this file when daemonized.
 


--mirror
 
 type: float
 
 How often to check whether connections should be moved, depending on
 \ ``read_only``\ .  Requires "--processlist" and "--execute".
 
 This option causes pt-query-digest to check every N seconds whether it is reading
 from a read-write server and executing against a read-only server, which is a
 sensible way to set up two servers if you're doing something like master-master
 replication.  The `http://code.google.com/p/mysql-master-master/ <http://code.google.com/p/mysql-master-master/>`_ master-master
 toolkit does this. The aim is to keep the passive server ready for failover,
 which is impossible without putting it under a realistic workload.
 


--order-by
 
 type: Array; default: Query_time:sum
 
 Sort events by this attribute and aggregate function.
 
 This is a comma-separated list of order-by expressions, one for each
 "--group-by" attribute.  The default \ ``Query_time:sum``\  is used for
 "--group-by" attributes without explicitly given "--order-by" attributes
 (that is, if you specify more "--group-by" attributes than corresponding
 "--order-by" attributes).  The syntax is \ ``attribute:aggregate``\ .  See
 "ATTRIBUTES" for valid attributes.  Valid aggregates are:
 
 
 .. code-block:: perl
 
     Aggregate Meaning
     ========= ============================
     sum       Sum/total attribute value
     min       Minimum attribute value
     max       Maximum attribute value
     cnt       Frequency/count of the query
 
 
 For example, the default \ ``Query_time:sum``\  means that queries in the
 query analysis report will be ordered (sorted) by their total query execution
 time ("Exec time").  \ ``Query_time:max``\  orders the queries by their
 maximum query execution time, so the query with the single largest
 \ ``Query_time``\  will be list first.  \ ``cnt``\  refers more to the frequency
 of the query as a whole, how often it appears; "Count" is its corresponding
 line in the query analysis report.  So any attribute and \ ``cnt``\  should yield
 the same report wherein queries are sorted by the number of times they
 appear.
 
 When parsing general logs ("--type" \ ``genlog``\ ), the default "--order-by"
 becomes \ ``Query_time:cnt``\ .  General logs do not report query times so only
 the \ ``cnt``\  aggregate makes sense because all query times are zero.
 
 If you specify an attribute that doesn't exist in the events, then
 pt-query-digest falls back to the default \ ``Query_time:sum``\  and prints a notice
 at the beginning of the report for each query class.  You can create attributes
 with "--filter" and order by them; see "ATTRIBUTES" for an example.
 


--outliers
 
 type: array; default: Query_time:1:10
 
 Report outliers by attribute:percentile:count.
 
 The syntax of this option is a comma-separated list of colon-delimited strings.
 The first field is the attribute by which an outlier is defined.  The second is
 a number that is compared to the attribute's 95th percentile.  The third is
 optional, and is compared to the attribute's cnt aggregate.  Queries that pass
 this specification are added to the report, regardless of any limits you
 specified in "--limit".
 
 For example, to report queries whose 95th percentile Query_time is at least 60
 seconds and which are seen at least 5 times, use the following argument:
 
 
 .. code-block:: perl
 
    --outliers Query_time:60:5
 
 
 You can specify an --outliers option for each value in "--group-by".
 


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
 


--pipeline-profile
 
 Print a profile of the pipeline processes.
 


--port
 
 short form: -P; type: int
 
 Port number to use for connection.
 


--print
 
 Print log events to STDOUT in standard slow-query-log format.
 


--print-iterations
 
 Print the start time for each "--iterations".
 
 This option causes a line like the following to be printed at the start
 of each "--iterations" report:
 
 
 .. code-block:: perl
 
    # Iteration 2 started at 2009-11-24T14:39:48.345780
 
 
 This line will print even if \ ``--no-report``\  is specified.  If \ ``--iterations 0``\ 
 is specified, each iteration number will be \ ``0``\ .
 


--processlist
 
 type: DSN
 
 Poll this DSN's processlist for queries, with "--interval" sleep between.
 
 If the connection fails, pt-query-digest tries to reopen it once per second. See
 also "--mirror".
 


--progress
 
 type: array; default: time,30
 
 Print progress reports to STDERR.  The value is a comma-separated list with two
 parts.  The first part can be percentage, time, or iterations; the second part
 specifies how often an update should be printed, in percentage, seconds, or
 number of iterations.
 


--read-timeout
 
 type: time; default: 0
 
 Wait this long for an event from the input; 0 to wait forever.
 
 This option sets the maximum time to wait for an event from the input.  It
 applies to all types of input except "--processlist".  If an
 event is not received after the specified time, the script stops reading the
 input and prints its reports.  If "--iterations" is 0 or greater than
 1, the next iteration will begin, else the script will exit.
 
 This option requires the Perl POSIX module.
 


--[no]report
 
 default: yes
 
 Print out reports on the aggregate results from "--group-by".
 
 This is the standard slow-log analysis functionality.  See "OUTPUT" for the
 description of what this does and what the results look like.
 


--report-all
 
 Include all queries, even if they have already been reviewed.
 


--report-format
 
 type: Array; default: rusage,date,hostname,files,header,profile,query_report,prepared
 
 Print these sections of the query analysis report.
 
 
 .. code-block:: perl
 
    SECTION      PRINTS
    ============ ======================================================
    rusage       CPU times and memory usage reported by ps
    date         Current local date and time
    hostname     Hostname of machine on which pt-query-digest was run
    files        Input files read/parse
    header       Summary of the entire analysis run
    profile      Compact table of queries for an overview of the report
    query_report Detailed information about each unique query
    prepared     Prepared statements
 
 
 The sections are printed in the order specified.  The rusage, date, files and
 header sections are grouped together if specified together; other sections are
 separated by blank lines.
 
 See "OUTPUT" for more information on the various parts of the query report.
 


--report-histogram
 
 type: string; default: Query_time
 
 Chart the distribution of this attribute's values.
 
 The distribution chart is limited to time-based attributes, so charting
 \ ``Rows_examined``\ , for example, will produce a useless chart.  Charts look
 like:
 
 
 .. code-block:: perl
 
    # Query_time distribution
    #   1us
    #  10us
    # 100us
    #   1ms
    #  10ms  ################################
    # 100ms  ################################################################
    #    1s  ########
    #  10s+
 
 
 A sparkline (see "SPARKLINES") of the full chart is also printed in the
 header for each query event.  The sparkline of that full chart is:
 
 
 .. code-block:: perl
 
    # Query_time sparkline: |    .^_ |
 
 
 The sparkline itself is the 8 characters between the pipes (\ ``|``\ ), one character
 for each of the 8 buckets (1us, 10us, etc.)  Four character codes are used
 to represent the approximate relation between each bucket's value:
 
 
 .. code-block:: perl
 
    _ . - ^
 
 
 The caret \ ``^``\  represents peaks (buckets with the most values), and
 the underscore \ ``_``\  represents lows (buckets with the least or at least
 one value).  The period \ ``.``\  and the hyphen \ ``-``\  represent buckets with values
 between these two extremes.  If a bucket has no values, a space is printed.
 So in the example above, the period represents the 10ms bucket, the caret
 the 100ms bucket, and the underscore the 1s bucket.
 
 See "OUTPUT" for more information.
 


--review
 
 type: DSN
 
 Store a sample of each class of query in this DSN.
 
 The argument specifies a table to store all unique query fingerprints in.  The
 table must have at least the following columns.  You can add more columns for
 your own special purposes, but they won't be used by pt-query-digest.  The
 following CREATE TABLE definition is also used for "--create-review-table".
 MAGIC_create_review:
 
 
 .. code-block:: perl
 
    CREATE TABLE query_review (
       checksum     BIGINT UNSIGNED NOT NULL PRIMARY KEY,
       fingerprint  TEXT NOT NULL,
       sample       TEXT NOT NULL,
       first_seen   DATETIME,
       last_seen    DATETIME,
       reviewed_by  VARCHAR(20),
       reviewed_on  DATETIME,
       comments     TEXT
    )
 
 
 The columns are as follows:
 
 
 .. code-block:: perl
 
    COLUMN       MEANING
    ===========  ===============
    checksum     A 64-bit checksum of the query fingerprint
    fingerprint  The abstracted version of the query; its primary key
    sample       The query text of a sample of the class of queries
    first_seen   The smallest timestamp of this class of queries
    last_seen    The largest timestamp of this class of queries
    reviewed_by  Initially NULL; if set, query is skipped thereafter
    reviewed_on  Initially NULL; not assigned any special meaning
    comments     Initially NULL; not assigned any special meaning
 
 
 Note that the \ ``fingerprint``\  column is the true primary key for a class of
 queries.  The \ ``checksum``\  is just a cryptographic hash of this value, which
 provides a shorter value that is very likely to also be unique.
 
 After parsing and aggregating events, your table should contain a row for each
 fingerprint.  This option depends on \ ``--group-by fingerprint``\  (which is the
 default).  It will not work otherwise.
 


--review-history
 
 type: DSN
 
 The table in which to store historical values for review trend analysis.
 
 Each time you review queries with "--review", pt-query-digest will save
 information into this table so you can see how classes of queries have changed
 over time.
 
 This DSN inherits unspecified values from "--review".  It should mention a
 table in which to store statistics about each class of queries.  pt-query-digest
 verifies the existence of the table, and your privileges to insert, delete and
 update on that table.
 
 pt-query-digest then inspects the columns in the table.  The table must have at
 least the following columns:
 
 
 .. code-block:: perl
 
    CREATE TABLE query_review_history (
      checksum     BIGINT UNSIGNED NOT NULL,
      sample       TEXT NOT NULL
    );
 
 
 Any columns not mentioned above are inspected to see if they follow a certain
 naming convention.  The column is special if the name ends with an underscore
 followed by any of these MAGIC_history_cols values:
 
 
 .. code-block:: perl
 
    pct|avt|cnt|sum|min|max|pct_95|stddev|median|rank
 
 
 If the column ends with one of those values, then the prefix is interpreted as
 the event attribute to store in that column, and the suffix is interpreted as
 the metric to be stored.  For example, a column named Query_time_min will be
 used to store the minimum Query_time for the class of events.  The presence of
 this column will also add Query_time to the "--select" list.
 
 The table should also have a primary key, but that is up to you, depending on
 how you want to store the historical data.  We suggest adding ts_min and ts_max
 columns and making them part of the primary key along with the checksum.  But
 you could also just add a ts_min column and make it a DATE type, so you'd get
 one row per class of queries per day.
 
 The default table structure follows.  The following MAGIC_create_review_history
 table definition is used for "--create-review-history-table":
 
 
 .. code-block:: perl
 
   CREATE TABLE query_review_history (
     checksum             BIGINT UNSIGNED NOT NULL,
     sample               TEXT NOT NULL,
     ts_min               DATETIME,
     ts_max               DATETIME,
     ts_cnt               FLOAT,
     Query_time_sum       FLOAT,
     Query_time_min       FLOAT,
     Query_time_max       FLOAT,
     Query_time_pct_95    FLOAT,
     Query_time_stddev    FLOAT,
     Query_time_median    FLOAT,
     Lock_time_sum        FLOAT,
     Lock_time_min        FLOAT,
     Lock_time_max        FLOAT,
     Lock_time_pct_95     FLOAT,
     Lock_time_stddev     FLOAT,
     Lock_time_median     FLOAT,
     Rows_sent_sum        FLOAT,
     Rows_sent_min        FLOAT,
     Rows_sent_max        FLOAT,
     Rows_sent_pct_95     FLOAT,
     Rows_sent_stddev     FLOAT,
     Rows_sent_median     FLOAT,
     Rows_examined_sum    FLOAT,
     Rows_examined_min    FLOAT,
     Rows_examined_max    FLOAT,
     Rows_examined_pct_95 FLOAT,
     Rows_examined_stddev FLOAT,
     Rows_examined_median FLOAT,
     -- Percona extended slowlog attributes 
     -- http://www.percona.com/docs/wiki/patches:slow_extended
     Rows_affected_sum             FLOAT,
     Rows_affected_min             FLOAT,
     Rows_affected_max             FLOAT,
     Rows_affected_pct_95          FLOAT,
     Rows_affected_stddev          FLOAT,
     Rows_affected_median          FLOAT,
     Rows_read_sum                 FLOAT,
     Rows_read_min                 FLOAT,
     Rows_read_max                 FLOAT,
     Rows_read_pct_95              FLOAT,
     Rows_read_stddev              FLOAT,
     Rows_read_median              FLOAT,
     Merge_passes_sum              FLOAT,
     Merge_passes_min              FLOAT,
     Merge_passes_max              FLOAT,
     Merge_passes_pct_95           FLOAT,
     Merge_passes_stddev           FLOAT,
     Merge_passes_median           FLOAT,
     InnoDB_IO_r_ops_min           FLOAT,
     InnoDB_IO_r_ops_max           FLOAT,
     InnoDB_IO_r_ops_pct_95        FLOAT,
     InnoDB_IO_r_ops_stddev        FLOAT,
     InnoDB_IO_r_ops_median        FLOAT,
     InnoDB_IO_r_bytes_min         FLOAT,
     InnoDB_IO_r_bytes_max         FLOAT,
     InnoDB_IO_r_bytes_pct_95      FLOAT,
     InnoDB_IO_r_bytes_stddev      FLOAT,
     InnoDB_IO_r_bytes_median      FLOAT,
     InnoDB_IO_r_wait_min          FLOAT,
     InnoDB_IO_r_wait_max          FLOAT,
     InnoDB_IO_r_wait_pct_95       FLOAT,
     InnoDB_IO_r_wait_stddev       FLOAT,
     InnoDB_IO_r_wait_median       FLOAT,
     InnoDB_rec_lock_wait_min      FLOAT,
     InnoDB_rec_lock_wait_max      FLOAT,
     InnoDB_rec_lock_wait_pct_95   FLOAT,
     InnoDB_rec_lock_wait_stddev   FLOAT,
     InnoDB_rec_lock_wait_median   FLOAT,
     InnoDB_queue_wait_min         FLOAT,
     InnoDB_queue_wait_max         FLOAT,
     InnoDB_queue_wait_pct_95      FLOAT,
     InnoDB_queue_wait_stddev      FLOAT,
     InnoDB_queue_wait_median      FLOAT,
     InnoDB_pages_distinct_min     FLOAT,
     InnoDB_pages_distinct_max     FLOAT,
     InnoDB_pages_distinct_pct_95  FLOAT,
     InnoDB_pages_distinct_stddev  FLOAT,
     InnoDB_pages_distinct_median  FLOAT,
     -- Boolean (Yes/No) attributes.  Only the cnt and sum are needed for these.
     -- cnt is how many times is attribute was recorded and sum is how many of
     -- those times the value was Yes.  Therefore sum/cnt * 100 = % of recorded
     -- times that the value was Yes.
     QC_Hit_cnt          FLOAT,
     QC_Hit_sum          FLOAT,
     Full_scan_cnt       FLOAT,
     Full_scan_sum       FLOAT,
     Full_join_cnt       FLOAT,
     Full_join_sum       FLOAT,
     Tmp_table_cnt       FLOAT,
     Tmp_table_sum       FLOAT,
     Disk_tmp_table_cnt  FLOAT,
     Disk_tmp_table_sum  FLOAT,
     Filesort_cnt        FLOAT,
     Filesort_sum        FLOAT,
     Disk_filesort_cnt   FLOAT,
     Disk_filesort_sum   FLOAT,
     PRIMARY KEY(checksum, ts_min, ts_max)
   );
 
 
 Note that we store the count (cnt) for the ts attribute only; it will be
 redundant to store this for other attributes.
 


--run-time
 
 type: time
 
 How long to run for each "--iterations".  The default is to run forever
 (you can interrupt with CTRL-C).  Because "--iterations" defaults to 1,
 if you only specify "--run-time", pt-query-digest runs for that amount of
 time and then exits.  The two options are specified together to do
 collect-and-report cycles.  For example, specifying "--iterations" \ ``4``\ 
 "--run-time" \ ``15m``\  with a continuous input (like STDIN or
 "--processlist") will cause pt-query-digest to run for 1 hour
 (15 minutes x 4), reporting four times, once at each 15 minute interval.
 


--run-time-mode
 
 type: string; default: clock
 
 Set what the value of "--run-time" operates on.  Following are the possible
 values for this option:
 
 
 clock
  
  "--run-time" specifies an amount of real clock time during which the tool
  should run for each "--iterations".
  
 
 
 event
  
  "--run-time" specifies an amount of log time.  Log time is determined by
  timestamps in the log.  The first timestamp seen is remembered, and each
  timestamp after that is compared to the first to determine how much log time
  has passed.  For example, if the first timestamp seen is \ ``12:00:00``\  and the
  next is \ ``12:01:30``\ , that is 1 minute and 30 seconds of log time.  The tool
  will read events until the log time is greater than or equal to the specified
  "--run-time" value.
  
  Since timestamps in logs are not always printed, or not always printed
  frequently, this mode varies in accuracy.
  
 
 
 interval
  
  "--run-time" specifies interval boundaries of log time into which events
  are divided and reports are generated.  This mode is different from the
  others because it doesn't specify how long to run.  The value of
  "--run-time" must be an interval that divides evenly into minutes, hours
  or days.  For example, \ ``5m``\  divides evenly into hours (60/5=12, so 12
  5 minutes intervals per hour) but \ ``7m``\  does not (60/7=8.6).
  
  Specifying \ ``--run-time-mode interval --run-time 30m --iterations 0``\  is
  similar to specifying \ ``--run-time-mode clock --run-time 30m --iterations 0``\ .
  In the latter case, pt-query-digest will run forever, producing reports every
  30 minutes, but this only works effectively with  continuous inputs like
  STDIN and the processlist.  For fixed inputs, like log files, the former
  example produces multiple reports by dividing the log into 30 minutes
  intervals based on timestamps.
  
  Intervals are calculated from the zeroth second/minute/hour in which a
  timestamp occurs, not from whatever time it specifies.  For example,
  with 30 minute intervals and a timestamp of \ ``12:10:30``\ , the interval
  is \ *not*\  \ ``12:10:30``\  to \ ``12:40:30``\ , it is \ ``12:00:00``\  to \ ``12:29:59``\ .
  Or, with 1 hour intervals, it is \ ``12:00:00``\  to \ ``12:59:59``\ .
  When a new timestamp exceeds the interval, a report is printed, and the
  next interval is recalculated based on the new timestamp.
  
  Since "--iterations" is 1 by default, you probably want to specify
  a new value else pt-query-digest will only get and report on the first
  interval from the log since 1 interval = 1 iteration.  If you want to
  get and report every interval in a log, specify "--iterations" \ ``0``\ .
  
 
 


--sample
 
 type: int
 
 Filter out all but the first N occurrences of each query.  The queries are
 filtered on the first value in "--group-by", so by default, this will filter
 by query fingerprint.  For example, \ ``--sample 2``\  will permit two sample queries
 for each fingerprint.  Useful in conjunction with "--print" to print out the
 queries.  You probably want to set \ ``--no-report``\  to avoid the overhead of
 aggregating and reporting if you're just using this to print out samples of
 queries.  A complete example:
 
 
 .. code-block:: perl
 
    pt-query-digest --sample 2 --no-report --print slow.log
 
 


--select
 
 type: Array
 
 Compute aggregate statistics for these attributes.
 
 By default pt-query-digest auto-detects, aggregates and prints metrics for
 every query attribute that it finds in the slow query log.  This option
 specifies a list of only the attributes that you want.  You can specify an
 alternative attribute with a colon.  For example, \ ``db:Schema``\  uses db if it's
 available, and Schema if it's not.
 
 Previously, pt-query-digest only aggregated these attributes:
 
 
 .. code-block:: perl
 
    Query_time,Lock_time,Rows_sent,Rows_examined,user,db:Schema,ts
 
 
 Attributes specified in the "--review-history" table will always be selected 
 even if you do not specify "--select".
 
 See also "--ignore-attributes" and "ATTRIBUTES".
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this
 string will be appended to SET and executed.
 


--shorten
 
 type: int; default: 1024
 
 Shorten long statements in reports.
 
 Shortens long statements, replacing the omitted portion with a \ ``/\*... omitted
 ...\*/``\  comment.  This applies only to the output in reports, not to information
 stored for "--review" or other places.  It prevents a large statement from
 causing difficulty in a report.  The argument is the preferred length of the
 shortened statement.  Not all statements can be shortened, but very large INSERT
 and similar statements often can; and so can IN() lists, although only the first
 such list in the statement will be shortened.
 
 If it shortens something beyond recognition, you can find the original statement
 in the log, at the offset shown in the report header (see "OUTPUT").
 


--show-all
 
 type: Hash
 
 Show all values for these attributes.
 
 By default pt-query-digest only shows as many of an attribute's value that
 fit on a single line.  This option allows you to specify attributes for which
 all values will be shown (line width is ignored).  This only works for
 attributes with string values like user, host, db, etc.  Multiple attributes
 can be specified, comma-separated.
 


--since
 
 type: string
 
 Parse only queries newer than this value (parse queries since this date).
 
 This option allows you to ignore queries older than a certain value and parse
 only those queries which are more recent than the value.  The value can be
 several types:
 
 
 .. code-block:: perl
 
    * Simple time value N with optional suffix: N[shmd], where
      s=seconds, h=hours, m=minutes, d=days (default s if no suffix
      given); this is like saying "since N[shmd] ago"
    * Full date with optional hours:minutes:seconds:
      YYYY-MM-DD [HH:MM::SS]
    * Short, MySQL-style date:
      YYMMDD [HH:MM:SS]
    * Any time expression evaluated by MySQL:
      CURRENT_DATE - INTERVAL 7 DAY
 
 
 If you give a MySQL time expression, then you must also specify a DSN
 so that pt-query-digest can connect to MySQL to evaluate the expression.  If you
 specify "--execute", "--explain", "--processlist", "--review"
 or "--review-history", then one of these DSNs will be used automatically.
 Otherwise, you must specify an "--aux-dsn" or pt-query-digest will die
 saying that the value is invalid.
 
 The MySQL time expression is wrapped inside a query like
 "SELECT UNIX_TIMESTAMP(<expression>)", so be sure that the expression is
 valid inside this query.  For example, do not use UNIX_TIMESTAMP() because
 UNIX_TIMESTAMP(UNIX_TIMESTAMP()) returns 0.
 
 Events are assumed to be in chronological--older events at the beginning of
 the log and newer events at the end of the log.  "--since" is strict: it
 ignores all queries until one is found that is new enough.  Therefore, if
 the query events are not consistently timestamped, some may be ignored which
 are actually new enough.
 
 See also "--until".
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--statistics
 
 Print statistics about internal counters.  This option is mostly for
 development and debugging.  The statistics report is printed for each
 iteration after all other reports, even if no events are processed or
 \ ``--no-report``\  is specified.  The statistics report looks like:
 
 
 .. code-block:: perl
 
     # No events processed.
  
     # Statistic                                        Count  %/Events
     # ================================================ ====== ========
     # events_read                                      142030   100.00
     # events_parsed                                     50430    35.51
     # events_aggregated                                     0     0.00
     # ignored_midstream_server_response                 18111    12.75
     # no_tcp_data                                       91600    64.49
     # pipeline_restarted_after_MemcachedProtocolParser 142030   100.00
     # pipeline_restarted_after_TcpdumpParser                1     0.00
     # unknown_client_command                                1     0.00
     # unknown_client_data                               32318    22.75
 
 
 The first column is the internal counter name; the second column is counter's
 count; and the third column is the count as a percentage of \ ``events_read``\ .
 
 In this case, it shows why no events were processed/aggregated: 100% of events
 were rejected by the \ ``MemcachedProtocolParser``\ .  Of those, 35.51% were data
 packets, but of these 12.75% of ignored mid-stream server response, one was
 an unknown client command, and 22.75% were unknown client data.  The other
 64.49% were TCP control packets (probably most ACKs).
 
 Since pt-query-digest is complex, you will probably need someone familiar
 with its code to decipher the statistics report.
 


--table-access
 
 Print a table access report.
 
 The table access report shows which tables are accessed by all the queries
 and if the access is a read or write.  The report looks like:
 
 
 .. code-block:: perl
 
    write `baz`.`tbl`
    read `baz`.`new_tbl`
    write `baz`.`tbl3`
    write `db6`.`tbl6`
 
 
 If you pipe the output to sort, the read and write tables will be grouped
 together and sorted alphabetically:
 
 
 .. code-block:: perl
 
    read `baz`.`new_tbl`
    write `baz`.`tbl`
    write `baz`.`tbl3`
    write `db6`.`tbl6`
 
 


--tcpdump-errors
 
 type: string
 
 Write the tcpdump data to this file on error.  If pt-query-digest doesn't
 parse the stream correctly for some reason, the session's packets since the
 last query event will be written out to create a usable test case.  If this
 happens, pt-query-digest will not raise an error; it will just discard the
 session's saved state and permit the tool to continue working.  See "tcpdump"
 for more information about parsing tcpdump output.
 


--timeline
 
 Show a timeline of events.
 
 This option makes pt-query-digest print another kind of report: a timeline of
 the events.  Each query is still grouped and aggregate into classes according to
 "--group-by", but then they are printed in chronological order.  The timeline
 report prints out the timestamp, interval, count and value of each classes.
 
 If all you want is the timeline report, then specify \ ``--no-report``\  to
 suppress the default query analysis report.  Otherwise, the timeline report
 will be printed at the end before the response-time profile
 (see "--report-format" and "OUTPUT").
 
 For example, this:
 
 
 .. code-block:: perl
 
    pt-query-digest /path/to/log --group-by distill --timeline
 
 
 will print something like:
 
 
 .. code-block:: perl
 
    # ########################################################
    # distill report
    # ########################################################
    # 2009-07-25 11:19:27 1+00:00:01   2 SELECT foo
    # 2009-07-27 11:19:30      00:01   2 SELECT bar
    # 2009-07-27 11:30:00 1+06:30:00   2 SELECT foo
 
 


--type
 
 type: Array
 
 The type of input to parse (default slowlog).  The permitted types are
 
 
 binlog
  
  Parse a binary log file.
  
 
 
 genlog
  
  Parse a MySQL general log file.  General logs lack a lot of "ATTRIBUTES",
  notably \ ``Query_time``\ .  The default "--order-by" for general logs
  changes to \ ``Query_time:cnt``\ .
  
 
 
 http
  
  Parse HTTP traffic from tcpdump.
  
 
 
 pglog
  
  Parse a log file in PostgreSQL format.  The parser will automatically recognize
  logs sent to syslog and transparently parse the syslog format, too.  The
  recommended configuration for logging in your postgresql.conf is as follows.
  
  The log_destination setting can be set to either syslog or stderr.  Syslog has
  the added benefit of not interleaving log messages from several sessions
  concurrently, which the parser cannot handle, so this might be better than
  stderr.  CSV-formatted logs are not supported at this time.
  
  The log_min_duration_statement setting should be set to 0 to capture all
  statements with their durations.  Alternatively, the parser will also recognize
  and handle various combinations of log_duration and log_statement.
  
  You may enable log_connections and log_disconnections, but this is optional.
  
  It is highly recommended to set your log_line_prefix to the following:
  
  
  .. code-block:: perl
  
     log_line_prefix = '%m c=%c,u=%u,D=%d '
  
  
  This lets the parser find timestamps with milliseconds, session IDs, users, and
  databases from the log.  If these items are missing, you'll simply get less
  information to analyze.  For compatibility with other log analysis tools such as
  PQA and pgfouine, various log line prefix formats are supported.  The general
  format is as follows: a timestamp can be detected and extracted (the syslog
  timestamp is NOT parsed), and a name=value list of properties can also.
  Although the suggested format is as shown above, any name=value list will be
  captured and interpreted by using the first letter of the 'name' part,
  lowercased, to determine the meaning of the item.  The lowercased first letter
  is interpreted to mean the same thing as PostgreSQL's built-in %-codes for the
  log_line_prefix format string.  For example, u means user, so unicorn=fred
  will be interpreted as user=fred; d means database, so D=john will be
  interpreted as database=john.  The pgfouine-suggested formatting is user=%u and
  db=%d, so it should Just Work regardless of which format you choose.  The main
  thing is to add as much information as possible into the log_line_prefix to
  permit richer analysis.
  
  Currently, only English locale messages are supported, so if your server's
  locale is set to something else, the log won't be parsed properly.  (Log
  messages with "duration:" and "statement:" won't be recognized.)
  
 
 
 slowlog
  
  Parse a log file in any variation of MySQL slow-log format.
  
 
 
 tcpdump
  
  Inspect network packets and decode the MySQL client protocol, extracting queries
  and responses from it.
  
  pt-query-digest does not actually watch the network (i.e. it does NOT "sniff
  packets").  Instead, it's just parsing the output of tcpdump.  You are
  responsible for generating this output; pt-query-digest does not do it for you.
  Then you send this to pt-query-digest as you would any log file: as files on the
  command line or to STDIN.
  
  The parser expects the input to be formatted with the following options: \ ``-x -n
  -q -tttt``\ .  For example, if you want to capture output from your local machine,
  you can do something like the following (the port must come last on FreeBSD):
  
  
  .. code-block:: perl
  
     tcpdump -s 65535 -x -nn -q -tttt -i any -c 1000 port 3306 \
       > mysql.tcp.txt
     pt-query-digest --type tcpdump mysql.tcp.txt
  
  
  The other tcpdump parameters, such as -s, -c, and -i, are up to you.  Just make
  sure the output looks like this (there is a line break in the first line to
  avoid man-page problems):
  
  
  .. code-block:: perl
  
     2009-04-12 09:50:16.804849 IP 127.0.0.1.42167
            > 127.0.0.1.3306: tcp 37
         0x0000:  4508 0059 6eb2 4000 4006 cde2 7f00 0001
         0x0010:  ....
  
  
  Remember tcpdump has a handy -c option to stop after it captures some number of
  packets!  That's very useful for testing your tcpdump command.  Note that
  tcpdump can't capture traffic on a Unix socket.  Read
  `http://bugs.mysql.com/bug.php?id=31577 <http://bugs.mysql.com/bug.php?id=31577>`_ if you're confused about this.
  
  Devananda Van Der Veen explained on the MySQL Performance Blog how to capture
  traffic without dropping packets on busy servers.  Dropped packets cause
  pt-query-digest to miss the response to a request, then see the response to a
  later request and assign the wrong execution time to the query.  You can change
  the filter to something like the following to help capture a subset of the
  queries.  (See `http://www.mysqlperformanceblog.com/?p=6092 <http://www.mysqlperformanceblog.com/?p=6092>`_ for details.)
  
  
  .. code-block:: perl
  
     tcpdump -i any -s 65535 -x -n -q -tttt \
        'port 3306 and tcp[1] & 7 == 2 and tcp[3] & 7 == 2'
  
  
  All MySQL servers running on port 3306 are automatically detected in the
  tcpdump output.  Therefore, if the tcpdump out contains packets from
  multiple servers on port 3306 (for example, 10.0.0.1:3306, 10.0.0.2:3306,
  etc.), all packets/queries from all these servers will be analyzed
  together as if they were one server.
  
  If you're analyzing traffic for a MySQL server that is not running on port
  3306, see "--watch-server".
  
  Also note that pt-query-digest may fail to report the database for queries
  when parsing tcpdump output.  The database is discovered only in the initial
  connect events for a new client or when <USE db> is executed.  If the tcpdump
  output contains neither of these, then pt-query-digest cannot discover the
  database.
  
  Server-side prepared statements are supported.  SSL-encrypted traffic cannot be
  inspected and decoded.
  
 
 
 memcached
  
  Similar to tcpdump, but the expected input is memcached packets
  instead of MySQL packets.  For example:
  
  
  .. code-block:: perl
  
     tcpdump -i any port 11211 -s 65535 -x -nn -q -tttt \
       > memcached.tcp.txt
     pt-query-digest --type memcached memcached.tcp.txt
  
  
  memcached uses port 11211 by default.
  
 
 


--until
 
 type: string
 
 Parse only queries older than this value (parse queries until this date).
 
 This option allows you to ignore queries newer than a certain value and parse
 only those queries which are older than the value.  The value can be one of
 the same types listed for "--since".
 
 Unlike "--since", "--until" is not strict: all queries are parsed until
 one has a timestamp that is equal to or greater than "--until".  Then
 all subsequent queries are ignored.
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


--variations
 
 type: Array
 
 Report the number of variations in these attributes' values.
 
 Variations show how many distinct values an attribute had within a class.
 The usual value for this option is \ ``arg``\  which shows how many distinct queries
 were in the class.  This can be useful to determine a query's cacheability.
 
 Distinct values are determined by CRC32 checksums of the attributes' values.
 These checksums are reported in the query report for attributes specified by
 this option, like:
 
 
 .. code-block:: perl
 
    # arg crc      109 (1/25%), 144 (1/25%)... 2 more
 
 
 In that class there were 4 distinct queries.  The checksums of the first two
 variations are shown, and each one occurred once (or, 25% of the time).
 
 The counts of distinct variations is approximate because only 1,000 variations
 are saved.  The mod (%) 1000 of the full CRC32 checksum is saved, so some
 distinct checksums are treated as equal.
 


--version
 
 Show version and exit.
 


--watch-server
 
 type: string
 
 This option tells pt-query-digest which server IP address and port (like
 "10.0.0.1:3306") to watch when parsing tcpdump (for "--type" tcpdump and
 memcached); all other servers are ignored.  If you don't specify it,
 pt-query-digest watches all servers by looking for any IP address using port
 3306 or "mysql".  If you're watching a server with a non-standard port, this
 won't work, so you must specify the IP address and port to watch.
 
 If you want to watch a mix of servers, some running on standard port 3306
 and some running on non-standard ports, you need to create separate
 tcpdump outputs for the non-standard port servers and then specify this
 option for each.  At present pt-query-digest cannot auto-detect servers on
 port 3306 and also be told to watch a server on a non-standard port.
 


--[no]zero-admin
 
 default: yes
 
 Zero out the Rows_XXX properties for administrator command events.
 


--[no]zero-bool
 
 default: yes
 
 Print 0% boolean values in report.
 



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
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-query-digest ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-query-digest <http://www.percona.com/bugs/pt-query-digest>`_.

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


This program is copyright 2008-2011 Percona Inc.
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


Percona Toolkit v0.9.5 released 2011-08-04

