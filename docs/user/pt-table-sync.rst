
#############
pt-table-sync
#############

.. highlight:: perl


****
NAME
****


pt-table-sync - Synchronize MySQL table data efficiently.


********
SYNOPSIS
********


Usage: pt-table-sync [OPTION...] DSN [DSN...]

pt-table-sync synchronizes data efficiently between MySQL tables.

This tool changes data, so for maximum safety, you should back up your data
before you use it.  When synchronizing a server that is a replication slave with
the --replicate or --sync-to-master methods, it \ **always**\  makes the changes on
the replication master, \ **never**\  the replication slave directly.  This is in
general the only safe way to bring a replica back in sync with its master;
changes to the replica are usually the source of the problems in the first
place.  However, the changes it makes on the master should be no-op changes that
set the data to their current values, and actually affect only the replica.
Please read the detailed documentation that follows to learn more about this.

Sync db.tbl on host1 to host2:


.. code-block:: perl

   pt-table-sync --execute h=host1,D=db,t=tbl h=host2


Sync all tables on host1 to host2 and host3:


.. code-block:: perl

   pt-table-sync --execute host1 host2 host3


Make slave1 have the same data as its replication master:


.. code-block:: perl

   pt-table-sync --execute --sync-to-master slave1


Resolve differences that pt-table-checksum found on all slaves of master1:


.. code-block:: perl

   pt-table-sync --execute --replicate test.checksum master1


Same as above but only resolve differences on slave1:


.. code-block:: perl

   pt-table-sync --execute --replicate test.checksum \
     --sync-to-master slave1


Sync master2 in a master-master replication configuration, where master2's copy
of db.tbl is known or suspected to be incorrect:


.. code-block:: perl

   pt-table-sync --execute --sync-to-master h=master2,D=db,t=tbl


Note that in the master-master configuration, the following will NOT do what you
want, because it will make changes directly on master2, which will then flow
through replication and change master1's data:


.. code-block:: perl

   # Don't do this in a master-master setup!
   pt-table-sync --execute h=master1,D=db,t=tbl master2



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

With great power comes great responsibility!  This tool changes data, so it is a
good idea to back up your data.  It is also very powerful, which means it is
very complex, so you should run it with the "--dry-run" option to see what it
will do, until you're familiar with its operation.  If you want to see which
rows are different, without changing any data, use "--print" instead of
"--execute".

Be careful when using pt-table-sync in any master-master setup.  Master-master
replication is inherently tricky, and it's easy to make mistakes.  You need to
be sure you're using the tool correctly for master-master replication.  See the
"SYNOPSIS" for the overview of the correct usage.

Also be careful with tables that have foreign key constraints with \ ``ON DELETE``\ 
or \ ``ON UPDATE``\  definitions because these might cause unintended changes on the
child tables.

In general, this tool is best suited when your tables have a primary key or
unique index.  Although it can synchronize data in tables lacking a primary key
or unique index, it might be best to synchronize that data by another means.

At the time of this release, there is a potential bug using
"--lock-and-rename" with MySQL 5.1, a bug detecting certain differences,
a bug using ROUND() across different platforms, and a bug mixing collations.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-table-sync <http://www.percona.com/bugs/pt-table-sync>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-table-sync does one-way and bidirectional synchronization of table data.
It does \ **not**\  synchronize table structures, indexes, or any other schema
objects.  The following describes one-way synchronization.
"BIDIRECTIONAL SYNCING" is described later.

This tool is complex and functions in several different ways.  To use it
safely and effectively, you should understand three things: the purpose
of "--replicate", finding differences, and specifying hosts.  These
three concepts are closely related and determine how the tool will run. 
The following is the abbreviated logic:


.. code-block:: perl

    if DSN has a t part, sync only that table:
       if 1 DSN:
          if --sync-to-master:
             The DSN is a slave.  Connect to its master and sync.
       if more than 1 DSN:
          The first DSN is the source.  Sync each DSN in turn.
    else if --replicate:
       if --sync-to-master:
          The DSN is a slave.  Connect to its master, find records
          of differences, and fix.
       else:
          The DSN is the master.  Find slaves and connect to each,
          find records of differences, and fix.
    else:
       if only 1 DSN and --sync-to-master:
          The DSN is a slave.  Connect to its master, find tables and
          filter with --databases etc, and sync each table to the master.
       else:
          find tables, filtering with --databases etc, and sync each
          DSN to the first.


pt-table-sync can run in one of two ways: with "--replicate" or without.
The default is to run without "--replicate" which causes pt-table-sync
to automatically find differences efficiently with one of several
algorithms (see "ALGORITHMS").  Alternatively, the value of
"--replicate", if specified, causes pt-table-sync to use the differences
already found by having previously ran pt-table-checksum with its own
\ ``--replicate``\  option.  Strictly speaking, you don't need to use
"--replicate" because pt-table-sync can find differences, but many
people use "--replicate" if, for example, they checksum regularly
using pt-table-checksum then fix differences as needed with pt-table-sync.
If you're unsure, read each tool's documentation carefully and decide for
yourself, or consult with an expert.

Regardless of whether "--replicate" is used or not, you need to specify
which hosts to sync.  There are two ways: with "--sync-to-master" or
without.  Specifying "--sync-to-master" makes pt-table-sync expect
one and only slave DSN on the command line.  The tool will automatically
discover the slave's master and sync it so that its data is the same as
its master.  This is accomplished by making changes on the master which
then flow through replication and update the slave to resolve its differences.
\ **Be careful though**\ : although this option specifies and syncs a single
slave, if there are other slaves on the same master, they will receive
via replication the changes intended for the slave that you're trying to
sync.

Alternatively, if you do not specify "--sync-to-master", the first
DSN given on the command line is the source host.  There is only ever
one source host.  If you do not also specify "--replicate", then you
must specify at least one other DSN as the destination host.  There
can be one or more destination hosts.  Source and destination hosts
must be independent; they cannot be in the same replication topology.
pt-table-sync will die with an error if it detects that a destination
host is a slave because changes are written directly to destination hosts
(and it's not safe to write directly to slaves).  Or, if you specify
"--replicate" (but not "--sync-to-master") then pt-table-sync expects
one and only one master DSN on the command line.  The tool will automatically
discover all the master's slaves and sync them to the master.  This is
the only way to sync several (all) slaves at once (because
"--sync-to-master" only specifies one slave).

Each host on the command line is specified as a DSN.  The first DSN
(or only DSN for cases like "--sync-to-master") provides default values
for other DSNs, whether those other DSNs are specified on the command line
or auto-discovered by the tool.  So in this example,


.. code-block:: perl

   pt-table-sync --execute h=host1,u=msandbox,p=msandbox h=host2


the host2 DSN inherits the \ ``u``\  and \ ``p``\  DSN parts from the host1 DSN.
Use the "--explain-hosts" option to see how pt-table-sync will interpret
the DSNs given on the command line.


******
OUTPUT
******


If you specify the "--verbose" option, you'll see information about the 
differences between the tables.  There is one row per table.  Each server is
printed separately.  For example,


.. code-block:: perl

   # Syncing h=host1,D=test,t=test1
   # DELETE REPLACE INSERT UPDATE ALGORITHM START    END      EXIT DATABASE.TABLE
   #      0       0      3      0 Chunk     13:00:00 13:00:17 2    test.test1


Table test.test1 on host1 required 3 \ ``INSERT``\  statements to synchronize
and it used the Chunk algorithm (see "ALGORITHMS").  The sync operation
for this table started at 13:00:00 and ended 17 seconds later (times taken
from \ ``NOW()``\  on the source host).  Because differences were found, its
"EXIT STATUS" was 2.

If you specify the "--print" option, you'll see the actual SQL statements
that the script uses to synchronize the table if "--execute" is also
specified.

If you want to see the SQL statements that pt-table-sync is using to select
chunks, nibbles, rows, etc., then specify "--print" once and "--verbose"
twice.  Be careful though: this can print a lot of SQL statements.

There are cases where no combination of \ ``INSERT``\ , \ ``UPDATE``\  or \ ``DELETE``\ 
statements can resolve differences without violating some unique key.  For
example, suppose there's a primary key on column a and a unique key on column b.
Then there is no way to sync these two tables with straightforward UPDATE
statements:


.. code-block:: perl

  +---+---+  +---+---+
  | a | b |  | a | b |
  +---+---+  +---+---+
  | 1 | 2 |  | 1 | 1 |
  | 2 | 1 |  | 2 | 2 |
  +---+---+  +---+---+


The tool rewrites queries to \ ``DELETE``\  and \ ``REPLACE``\  in this case.  This is
automatically handled after the first index violation, so you don't have to
worry about it.


******************
REPLICATION SAFETY
******************


Synchronizing a replication master and slave safely is a non-trivial problem, in
general.  There are all sorts of issues to think about, such as other processes
changing data, trying to change data on the slave, whether the destination and
source are a master-master pair, and much more.

In general, the safe way to do it is to change the data on the master, and let
the changes flow through replication to the slave like any other changes.
However, this works only if it's possible to REPLACE into the table on the
master.  REPLACE works only if there's a unique index on the table (otherwise it
just acts like an ordinary INSERT).

If your table has unique keys, you should use the "--sync-to-master" and/or
"--replicate" options to sync a slave to its master.  This will generally do
the right thing.  When there is no unique key on the table, there is no choice
but to change the data on the slave, and pt-table-sync will detect that you're
trying to do so.  It will complain and die unless you specify
\ ``--no-check-slave``\  (see "--[no]check-slave").

If you're syncing a table without a primary or unique key on a master-master
pair, you must change the data on the destination server.  Therefore, you need
to specify \ ``--no-bin-log``\  for safety (see "--[no]bin-log").  If you don't,
the changes you make on the destination server will replicate back to the
source server and change the data there!

The generally safe thing to do on a master-master pair is to use the
"--sync-to-master" option so you don't change the data on the destination
server.  You will also need to specify \ ``--no-check-slave``\  to keep
pt-table-sync from complaining that it is changing data on a slave.


**********
ALGORITHMS
**********


pt-table-sync has a generic data-syncing framework which uses different
algorithms to find differences.  The tool automatically chooses the best
algorithm for each table based on indexes, column types, and the algorithm
preferences specified by "--algorithms".  The following algorithms are
available, listed in their default order of preference:


Chunk
 
 Finds an index whose first column is numeric (including date and time types),
 and divides the column's range of values into chunks of approximately
 "--chunk-size" rows.  Syncs a chunk at a time by checksumming the entire
 chunk.  If the chunk differs on the source and destination, checksums each
 chunk's rows individually to find the rows that differ.
 
 It is efficient when the column has sufficient cardinality to make the chunks
 end up about the right size.
 
 The initial per-chunk checksum is quite small and results in minimal network
 traffic and memory consumption.  If a chunk's rows must be examined, only the
 primary key columns and a checksum are sent over the network, not the entire
 row.  If a row is found to be different, the entire row will be fetched, but not
 before.
 


Nibble
 
 Finds an index and ascends the index in fixed-size nibbles of "--chunk-size"
 rows, using a non-backtracking algorithm (see pt-archiver for more on this
 algorithm).  It is very similar to "Chunk", but instead of pre-calculating
 the boundaries of each piece of the table based on index cardinality, it uses
 \ ``LIMIT``\  to define each nibble's upper limit, and the previous nibble's upper
 limit to define the lower limit.
 
 It works in steps: one query finds the row that will define the next nibble's
 upper boundary, and the next query checksums the entire nibble.  If the nibble
 differs between the source and destination, it examines the nibble row-by-row,
 just as "Chunk" does.
 


GroupBy
 
 Selects the entire table grouped by all columns, with a COUNT(\*) column added.
 Compares all columns, and if they're the same, compares the COUNT(\*) column's
 value to determine how many rows to insert or delete into the destination.
 Works on tables with no primary key or unique index.
 


Stream
 
 Selects the entire table in one big stream and compares all columns.  Selects
 all columns.  Much less efficient than the other algorithms, but works when
 there is no suitable index for them to use.
 


Future Plans
 
 Possibilities for future algorithms are TempTable (what I originally called
 bottom-up in earlier versions of this tool), DrillDown (what I originally
 called top-down), and GroupByPrefix (similar to how SqlYOG Job Agent works).
 Each algorithm has strengths and weaknesses.  If you'd like to implement your
 favorite technique for finding differences between two sources of data on
 possibly different servers, I'm willing to help.  The algorithms adhere to a
 simple interface that makes it pretty easy to write your own.
 



*********************
BIDIRECTIONAL SYNCING
*********************


Bidirectional syncing is a new, experimental feature.  To make it work
reliably there are a number of strict limitations:


.. code-block:: perl

   * only works when syncing one server to other independent servers
   * does not work in any way with replication
   * requires that the table(s) are chunkable with the Chunk algorithm
   * is not N-way, only bidirectional between two servers at a time
   * does not handle DELETE changes


For example, suppose we have three servers: c1, r1, r2.  c1 is the central
server, a pseudo-master to the other servers (viz. r1 and r2 are not slaves
to c1).  r1 and r2 are remote servers.  Rows in table foo are updated and
inserted on all three servers and we want to synchronize all the changes
between all the servers.  Table foo has columns:


.. code-block:: perl

   id    int PRIMARY KEY
   ts    timestamp auto updated
   name  varchar


Auto-increment offsets are used so that new rows from any server do not
create conflicting primary key (id) values.  In general, newer rows, as
determined by the ts column, take precedence when a same but differing row
is found during the bidirectional sync.  "Same but differing" means that
two rows have the same primary key (id) value but different values for some
other column, like the name column in this example.  Same but differing
conflicts are resolved by a "conflict".  A conflict compares some column of
the competing rows to determine a "winner".  The winning row becomes the
source and its values are used to update the other row.

There are subtle differences between three columns used to achieve
bidirectional syncing that you should be familiar with: chunk column
("--chunk-column"), comparison column(s) ("--columns"), and conflict
column ("--conflict-column").  The chunk column is only used to chunk the
table; e.g. "WHERE id >= 5 AND id < 10".  Chunks are checksummed and when
chunk checksums reveal a difference, the tool selects the rows in that
chunk and checksums the "--columns" for each row.  If a column checksum
differs, the rows have one or more conflicting column values.  In a
traditional unidirectional sync, the conflict is a moot point because it can
be resolved simply by updating the entire destination row with the source
row's values.  In a bidirectional sync, however, the "--conflict-column"
(in accordance with other \ ``--conflict-\*``\  options list below) is compared
to determine which row is "correct" or "authoritative"; this row becomes
the "source".

To sync all three servers completely, two runs of pt-table-sync are required.
The first run syncs c1 and r1, then syncs c1 and r2 including any changes
from r1.  At this point c1 and r2 are completely in sync, but r1 is missing
any changes from r2 because c1 didn't have these changes when it and r1
were synced.  So a second run is needed which syncs the servers in the same
order, but this time when c1 and r1 are synced r1 gets r2's changes.

The tool does not sync N-ways, only bidirectionally between the first DSN
given on the command line and each subsequent DSN in turn.  So the tool in
this example would be ran twice like:


.. code-block:: perl

   pt-table-sync --bidirectional h=c1 h=r1 h=r2


The "--bidirectional" option enables this feature and causes various
sanity checks to be performed.  You must specify other options that tell
pt-table-sync how to resolve conflicts for same but differing rows.
These options are:


.. code-block:: perl

   * --conflict-column
   * --conflict-comparison
   * --conflict-value
   * --conflict-threshold
   * --conflict-error">  (optional)


Use "--print" to test this option before "--execute".  The printed
SQL statements will have comments saying on which host the statement
would be executed if you used "--execute".

Technical side note: the first DSN is always the "left" server and the other
DSNs are always the "right" server.  Since either server can become the source
or destination it's confusing to think of them as "src" and "dst".  Therefore,
they're generically referred to as left and right.  It's easy to remember
this because the first DSN is always to the left of the other server DSNs on
the command line.


***********
EXIT STATUS
***********


The following are the exit statuses (also called return values, or return codes)
when pt-table-sync finishes and exits.


.. code-block:: perl

    STATUS  MEANING
    ======  =======================================================
    0       Success.
    1       Internal error.
    2       At least one table differed on the destination.
    3       Combination of 1 and 2.



*******
OPTIONS
*******


Specify at least one of "--print", "--execute", or "--dry-run".

"--where" and "--replicate" are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
"SYNOPSIS" and usage information for details.


--algorithms
 
 type: string; default: Chunk,Nibble,GroupBy,Stream
 
 Algorithm to use when comparing the tables, in order of preference.
 
 For each table, pt-table-sync will check if the table can be synced with
 the given algorithms in the order that they're given.  The first algorithm
 that can sync the table is used.  See "ALGORITHMS".
 


--ask-pass
 
 Prompt for a password when connecting to MySQL.
 


--bidirectional
 
 Enable bidirectional sync between first and subsequent hosts.
 
 See "BIDIRECTIONAL SYNCING" for more information.
 


--[no]bin-log
 
 default: yes
 
 Log to the binary log (\ ``SET SQL_LOG_BIN=1``\ ).
 
 Specifying \ ``--no-bin-log``\  will \ ``SET SQL_LOG_BIN=0``\ .
 


--buffer-in-mysql
 
 Instruct MySQL to buffer queries in its memory.
 
 This option adds the \ ``SQL_BUFFER_RESULT``\  option to the comparison queries.
 This causes MySQL to execute the queries and place them in a temporary table
 internally before sending the results back to pt-table-sync.  The advantage of
 this strategy is that pt-table-sync can fetch rows as desired without using a
 lot of memory inside the Perl process, while releasing locks on the MySQL table
 (to reduce contention with other queries).  The disadvantage is that it uses
 more memory on the MySQL server instead.
 
 You probably want to leave "--[no]buffer-to-client" enabled too, because
 buffering into a temp table and then fetching it all into Perl's memory is
 probably a silly thing to do.  This option is most useful for the GroupBy and
 Stream algorithms, which may fetch a lot of data from the server.
 


--[no]buffer-to-client
 
 default: yes
 
 Fetch rows one-by-one from MySQL while comparing.
 
 This option enables \ ``mysql_use_result``\  which causes MySQL to hold the selected
 rows on the server until the tool fetches them.  This allows the tool to use
 less memory but may keep the rows locked on the server longer.
 
 If this option is disabled by specifying \ ``--no-buffer-to-client``\  then
 \ ``mysql_store_result``\  is used which causes MySQL to send all selected rows to
 the tool at once.  This may result in the results "cursor" being held open for
 a shorter time on the server, but if the tables are large, it could take a long
 time anyway, and use all your memory.
 
 For most non-trivial data sizes, you want to leave this option enabled.
 
 This option is disabled when "--bidirectional" is used.
 


--charset
 
 short form: -A; type: string
 
 Default character set.  If the value is utf8, sets Perl's binmode on
 STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
 runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
 binmode on STDOUT without the utf8 layer, and runs SET NAMES after
 connecting to MySQL.
 


--[no]check-master
 
 default: yes
 
 With "--sync-to-master", try to verify that the detected
 master is the real master.
 


--[no]check-privileges
 
 default: yes
 
 Check that user has all necessary privileges on source and destination table.
 


--[no]check-slave
 
 default: yes
 
 Check whether the destination server is a slave.
 
 If the destination server is a slave, it's generally unsafe to make changes on
 it.  However, sometimes you have to; "--replace" won't work unless there's a
 unique index, for example, so you can't make changes on the master in that
 scenario.  By default pt-table-sync will complain if you try to change data on
 a slave.  Specify \ ``--no-check-slave``\  to disable this check.  Use it at your own
 risk.
 


--[no]check-triggers
 
 default: yes
 
 Check that no triggers are defined on the destination table.
 
 Triggers were introduced in MySQL v5.0.2, so for older versions this option
 has no effect because triggers will not be checked.
 


--chunk-column
 
 type: string
 
 Chunk the table on this column.
 


--chunk-index
 
 type: string
 
 Chunk the table using this index.
 


--chunk-size
 
 type: string; default: 1000
 
 Number of rows or data size per chunk.
 
 The size of each chunk of rows for the "Chunk" and "Nibble" algorithms.
 The size can be either a number of rows, or a data size.  Data sizes are
 specified with a suffix of k=kibibytes, M=mebibytes, G=gibibytes.  Data sizes
 are converted to a number of rows by dividing by the average row length.
 


--columns
 
 short form: -c; type: array
 
 Compare this comma-separated list of columns.
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--conflict-column
 
 type: string
 
 Compare this column when rows conflict during a "--bidirectional" sync.
 
 When a same but differing row is found the value of this column from each
 row is compared according to "--conflict-comparison", "--conflict-value"
 and "--conflict-threshold" to determine which row has the correct data and
 becomes the source.  The column can be any type for which there is an
 appropriate "--conflict-comparison" (this is almost all types except, for
 example, blobs).
 
 This option only works with "--bidirectional".
 See "BIDIRECTIONAL SYNCING" for more information.
 


--conflict-comparison
 
 type: string
 
 Choose the "--conflict-column" with this property as the source.
 
 The option affects how the "--conflict-column" values from the conflicting
 rows are compared.  Possible comparisons are one of these MAGIC_comparisons:
 
 
 .. code-block:: perl
 
    newest|oldest|greatest|least|equals|matches
  
    COMPARISON  CHOOSES ROW WITH
    ==========  =========================================================
    newest      Newest temporal --conflict-column value
    oldest      Oldest temporal --conflict-column value
    greatest    Greatest numerical "--conflict-column value
    least       Least numerical --conflict-column value
    equals      --conflict-column value equal to --conflict-value
    matches     --conflict-column value matching Perl regex pattern
                --conflict-value
 
 
 This option only works with "--bidirectional".
 See "BIDIRECTIONAL SYNCING" for more information.
 


--conflict-error
 
 type: string; default: warn
 
 How to report unresolvable conflicts and conflict errors
 
 This option changes how the user is notified when a conflict cannot be
 resolved or causes some kind of error.  Possible values are:
 
 
 .. code-block:: perl
 
    * warn: Print a warning to STDERR about the unresolvable conflict
    * die:  Die, stop syncing, and print a warning to STDERR
 
 
 This option only works with "--bidirectional".
 See "BIDIRECTIONAL SYNCING" for more information.
 


--conflict-threshold
 
 type: string
 
 Amount by which one "--conflict-column" must exceed the other.
 
 The "--conflict-threshold" prevents a conflict from being resolved if
 the absolute difference between the two "--conflict-column" values is
 less than this amount.  For example, if two "--conflict-column" have
 timestamp values "2009-12-01 12:00:00" and "2009-12-01 12:05:00" the difference
 is 5 minutes.  If "--conflict-threshold" is set to "5m" the conflict will
 be resolved, but if "--conflict-threshold" is set to "6m" the conflict
 will fail to resolve because the difference is not greater than or equal
 to 6 minutes.  In this latter case, "--conflict-error" will report
 the failure.
 
 This option only works with "--bidirectional".
 See "BIDIRECTIONAL SYNCING" for more information.
 


--conflict-value
 
 type: string
 
 Use this value for certain "--conflict-comparison".
 
 This option gives the value for \ ``equals``\  and \ ``matches``\ 
 "--conflict-comparison".
 
 This option only works with "--bidirectional".
 See "BIDIRECTIONAL SYNCING" for more information.
 


--databases
 
 short form: -d; type: hash
 
 Sync only this comma-separated list of databases.
 
 A common request is to sync tables from one database with tables from another
 database on the same or different server.  This is not yet possible.
 "--databases" will not do it, and you can't do it with the D part of the DSN
 either because in the absence of a table name it assumes the whole server
 should be synced and the D part controls only the connection's default database.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute pathname.
 


--dry-run
 
 Analyze, decide the sync algorithm to use, print and exit.
 
 Implies "--verbose" so you can see the results.  The results are in the same
 output format that you'll see from actually running the tool, but there will be
 zeros for rows affected.  This is because the tool actually executes, but stops
 before it compares any data and just returns zeros.  The zeros do not mean there
 are no changes to be made.
 


--engines
 
 short form: -e; type: hash
 
 Sync only this comma-separated list of storage engines.
 


--execute
 
 Execute queries to make the tables have identical data.
 
 This option makes pt-table-sync actually sync table data by executing all
 the queries that it created to resolve table differences.  Therefore, \ **the
 tables will be changed!**\   And unless you also specify "--verbose", the
 changes will be made silently.  If this is not what you want, see
 "--print" or "--dry-run".
 


--explain-hosts
 
 Print connection information and exit.
 
 Print out a list of hosts to which pt-table-sync will connect, with all
 the various connection options, and exit.
 


--float-precision
 
 type: int
 
 Precision for \ ``FLOAT``\  and \ ``DOUBLE``\  number-to-string conversion.  Causes FLOAT
 and DOUBLE values to be rounded to the specified number of digits after the
 decimal point, with the ROUND() function in MySQL.  This can help avoid
 checksum mismatches due to different floating-point representations of the same
 values on different MySQL versions and hardware.  The default is no rounding;
 the values are converted to strings by the CONCAT() function, and MySQL chooses
 the string representation.  If you specify a value of 2, for example, then the
 values 1.008 and 1.009 will be rounded to 1.01, and will checksum as equal.
 


--[no]foreign-key-checks
 
 default: yes
 
 Enable foreign key checks (\ ``SET FOREIGN_KEY_CHECKS=1``\ ).
 
 Specifying \ ``--no-foreign-key-checks``\  will \ ``SET FOREIGN_KEY_CHECKS=0``\ .
 


--function
 
 type: string
 
 Which hash function you'd like to use for checksums.
 
 The default is \ ``CRC32``\ .  Other good choices include \ ``MD5``\  and \ ``SHA1``\ .  If you
 have installed the \ ``FNV_64``\  user-defined function, \ ``pt-table-sync``\  will detect
 it and prefer to use it, because it is much faster than the built-ins.  You can
 also use MURMUR_HASH if you've installed that user-defined function.  Both of
 these are distributed with Maatkit.  See pt-table-checksum for more
 information and benchmarks.
 


--help
 
 Show help and exit.
 


--[no]hex-blob
 
 default: yes
 
 \ ``HEX()``\  \ ``BLOB``\ , \ ``TEXT``\  and \ ``BINARY``\  columns.
 
 When row data from the source is fetched to create queries to sync the
 data (i.e. the queries seen with "--print" and executed by "--execute"),
 binary columns are wrapped in HEX() so the binary data does not produce
 an invalid SQL statement.  You can disable this option but you probably
 shouldn't.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--ignore-columns
 
 type: Hash
 
 Ignore this comma-separated list of column names in comparisons.
 
 This option causes columns not to be compared.  However, if a row is determined
 to differ between tables, all columns in that row will be synced, regardless.
 (It is not currently possible to exclude columns from the sync process itself,
 only from the comparison.)
 


--ignore-databases
 
 type: Hash
 
 Ignore this comma-separated list of databases.
 


--ignore-engines
 
 type: Hash; default: FEDERATED,MRG_MyISAM
 
 Ignore this comma-separated list of storage engines.
 


--ignore-tables
 
 type: Hash
 
 Ignore this comma-separated list of tables.
 
 Table names may be qualified with the database name.
 


--[no]index-hint
 
 default: yes
 
 Add FORCE/USE INDEX hints to the chunk and row queries.
 
 By default \ ``pt-table-sync``\  adds a FORCE/USE INDEX hint to each SQL statement
 to coerce MySQL into using the index chosen by the sync algorithm or specified
 by "--chunk-index".  This is usually a good thing, but in rare cases the
 index may not be the best for the query so you can suppress the index hint
 by specifying \ ``--no-index-hint``\  and let MySQL choose the index.
 
 This does not affect the queries printed by "--print"; it only affects the
 chunk and row queries that \ ``pt-table-sync``\  uses to select and compare rows.
 


--lock
 
 type: int
 
 Lock tables: 0=none, 1=per sync cycle, 2=per table, or 3=globally.
 
 This uses \ ``LOCK TABLES``\ .  This can help prevent tables being changed while
 you're examining them.  The possible values are as follows:
 
 
 .. code-block:: perl
 
    VALUE  MEANING
    =====  =======================================================
    0      Never lock tables.
    1      Lock and unlock one time per sync cycle (as implemented
           by the syncing algorithm).  This is the most granular
           level of locking available.  For example, the Chunk
           algorithm will lock each chunk of C<N> rows, and then
           unlock them if they are the same on the source and the
           destination, before moving on to the next chunk.
    2      Lock and unlock before and after each table.
    3      Lock and unlock once for every server (DSN) synced, with
           C<FLUSH TABLES WITH READ LOCK>.
 
 
 A replication slave is never locked if "--replicate" or "--sync-to-master"
 is specified, since in theory locking the table on the master should prevent any
 changes from taking place.  (You are not changing data on your slave, right?)
 If "--wait" is given, the master (source) is locked and then the tool waits
 for the slave to catch up to the master before continuing.
 
 If \ ``--transaction``\  is specified, \ ``LOCK TABLES``\  is not used.  Instead, lock
 and unlock are implemented by beginning and committing transactions.
 The exception is if "--lock" is 3.
 
 If \ ``--no-transaction``\  is specified, then \ ``LOCK TABLES``\  is used for any
 value of "--lock". See "--[no]transaction".
 


--lock-and-rename
 
 Lock the source and destination table, sync, then swap names.  This is useful as
 a less-blocking ALTER TABLE, once the tables are reasonably in sync with each
 other (which you may choose to accomplish via any number of means, including
 dump and reload or even something like pt-archiver).  It requires exactly two
 DSNs and assumes they are on the same server, so it does no waiting for
 replication or the like.  Tables are locked with LOCK TABLES.
 


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
 


--print
 
 Print queries that will resolve differences.
 
 If you don't trust \ ``pt-table-sync``\ , or just want to see what it will do, this
 is a good way to be safe.  These queries are valid SQL and you can run them
 yourself if you want to sync the tables manually.
 


--recursion-method
 
 type: string
 
 Preferred recursion method used to find slaves.
 
 Possible methods are:
 
 
 .. code-block:: perl
 
    METHOD       USES
    ===========  ================
    processlist  SHOW PROCESSLIST
    hosts        SHOW SLAVE HOSTS
 
 
 The processlist method is preferred because SHOW SLAVE HOSTS is not reliable.
 However, the hosts method is required if the server uses a non-standard
 port (not 3306).  Usually pt-table-sync does the right thing and finds
 the slaves, but you may give a preferred method and it will be used first.
 If it doesn't find any slaves, the other methods will be tried.
 


--replace
 
 Write all \ ``INSERT``\  and \ ``UPDATE``\  statements as \ ``REPLACE``\ .
 
 This is automatically switched on as needed when there are unique index
 violations.
 


--replicate
 
 type: string
 
 Sync tables listed as different in this table.
 
 Specifies that \ ``pt-table-sync``\  should examine the specified table to find data
 that differs.  The table is exactly the same as the argument of the same name to
 pt-table-checksum.  That is, it contains records of which tables (and ranges
 of values) differ between the master and slave.
 
 For each table and range of values that shows differences between the master and
 slave, \ ``pt-table-checksum``\  will sync that table, with the appropriate \ ``WHERE``\ 
 clause, to its master.
 
 This automatically sets "--wait" to 60 and causes changes to be made on the
 master instead of the slave.
 
 If "--sync-to-master" is specified, the tool will assume the server you
 specified is the slave, and connect to the master as usual to sync.
 
 Otherwise, it will try to use \ ``SHOW PROCESSLIST``\  to find slaves of the server
 you specified.  If it is unable to find any slaves via \ ``SHOW PROCESSLIST``\ , it
 will inspect \ ``SHOW SLAVE HOSTS``\  instead.  You must configure each slave's
 \ ``report-host``\ , \ ``report-port``\  and other options for this to work right.  After
 finding slaves, it will inspect the specified table on each slave to find data
 that needs to be synced, and sync it.
 
 The tool examines the master's copy of the table first, assuming that the master
 is potentially a slave as well.  Any table that shows differences there will
 \ **NOT**\  be synced on the slave(s).  For example, suppose your replication is set
 up as A->B, B->C, B->D.  Suppose you use this argument and specify server B.
 The tool will examine server B's copy of the table.  If it looks like server B's
 data in table \ ``test.tbl1``\  is different from server A's copy, the tool will not
 sync that table on servers C and D.
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this
 string will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--sync-to-master
 
 Treat the DSN as a slave and sync it to its master.
 
 Treat the server you specified as a slave.  Inspect \ ``SHOW SLAVE STATUS``\ ,
 connect to the server's master, and treat the master as the source and the slave
 as the destination.  Causes changes to be made on the master.  Sets "--wait"
 to 60 by default, sets "--lock" to 1 by default, and disables
 "--[no]transaction" by default.  See also "--replicate", which changes
 this option's behavior.
 


--tables
 
 short form: -t; type: hash
 
 Sync only this comma-separated list of tables.
 
 Table names may be qualified with the database name.
 


--timeout-ok
 
 Keep going if "--wait" fails.
 
 If you specify "--wait" and the slave doesn't catch up to the master's
 position before the wait times out, the default behavior is to abort.  This
 option makes the tool keep going anyway.  \ **Warning**\ : if you are trying to get a
 consistent comparison between the two servers, you probably don't want to keep
 going after a timeout.
 


--[no]transaction
 
 Use transactions instead of \ ``LOCK TABLES``\ .
 
 The granularity of beginning and committing transactions is controlled by
 "--lock".  This is enabled by default, but since "--lock" is disabled by
 default, it has no effect.
 
 Most options that enable locking also disable transactions by default, so if
 you want to use transactional locking (via \ ``LOCK IN SHARE MODE``\  and \ ``FOR
 UPDATE``\ , you must specify \ ``--transaction``\  explicitly.
 
 If you don't specify \ ``--transaction``\  explicitly \ ``pt-table-sync``\  will decide on
 a per-table basis whether to use transactions or table locks.  It currently
 uses transactions on InnoDB tables, and table locks on all others.
 
 If \ ``--no-transaction``\  is specified, then \ ``pt-table-sync``\  will not use
 transactions at all (not even for InnoDB tables) and locking is controlled
 by "--lock".
 
 When enabled, either explicitly or implicitly, the transaction isolation level
 is set \ ``REPEATABLE READ``\  and transactions are started \ ``WITH CONSISTENT
 SNAPSHOT``\ .
 


--trim
 
 \ ``TRIM()``\  \ ``VARCHAR``\  columns in \ ``BIT_XOR``\  and \ ``ACCUM``\  modes.  Helps when
 comparing MySQL 4.1 to >= 5.0.
 
 This is useful when you don't care about the trailing space differences between
 MySQL versions which vary in their handling of trailing spaces. MySQL 5.0 and 
 later all retain trailing spaces in \ ``VARCHAR``\ , while previous versions would 
 remove them.
 


--[no]unique-checks
 
 default: yes
 
 Enable unique key checks (\ ``SET UNIQUE_CHECKS=1``\ ).
 
 Specifying \ ``--no-unique-checks``\  will \ ``SET UNIQUE_CHECKS=0``\ .
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


--verbose
 
 short form: -v; cumulative: yes
 
 Print results of sync operations.
 
 See "OUTPUT" for more details about the output.
 


--version
 
 Show version and exit.
 


--wait
 
 short form: -w; type: time
 
 How long to wait for slaves to catch up to their master.
 
 Make the master wait for the slave to catch up in replication before comparing
 the tables.  The value is the number of seconds to wait before timing out (see
 also "--timeout-ok").  Sets "--lock" to 1 and "--[no]transaction" to 0
 by default.  If you see an error such as the following,
 
 
 .. code-block:: perl
 
    MASTER_POS_WAIT returned -1
 
 
 It means the timeout was exceeded and you need to increase it.
 
 The default value of this option is influenced by other options.  To see what
 value is in effect, run with "--help".
 
 To disable waiting entirely (except for locks), specify "--wait" 0.  This
 helps when the slave is lagging on tables that are not being synced.
 


--where
 
 type: string
 
 \ ``WHERE``\  clause to restrict syncing to part of the table.
 


--[no]zero-chunk
 
 default: yes
 
 Add a chunk for rows with zero or zero-equivalent values.  The only has an
 effect when "--chunk-size" is specified.  The purpose of the zero chunk
 is to capture a potentially large number of zero values that would imbalance
 the size of the first chunk.  For example, if a lot of negative numbers were
 inserted into an unsigned integer column causing them to be stored as zeros,
 then these zero values are captured by the zero chunk instead of the first
 chunk and all its non-zero values.
 



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
 
 Database containing the table to be synced.
 


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
 
 copy: yes
 
 Table to be synced.
 


\* u
 
 dsn: user; copy: yes
 
 User for login if not current user.
 



***********
ENVIRONMENT
***********


The environment variable \ ``PTDEBUG``\  enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:


.. code-block:: perl

    PTDEBUG=1 pt-table-sync ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-table-sync <http://www.percona.com/bugs/pt-table-sync>`_.

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


***************
ACKNOWLEDGMENTS
***************


My work is based in part on Giuseppe Maxia's work on distributed databases,
`http://www.sysadminmag.com/articles/2004/0408/ <http://www.sysadminmag.com/articles/2004/0408/>`_ and code derived from that
article.  There is more explanation, and a link to the code, at
`http://www.perlmonks.org/?node_id=381053 <http://www.perlmonks.org/?node_id=381053>`_.

Another programmer extended Maxia's work even further.  Fabien Coelho changed
and generalized Maxia's technique, introducing symmetry and avoiding some
problems that might have caused too-frequent checksum collisions.  This work
grew into pg_comparator, `http://www.coelho.net/pg_comparator/ <http://www.coelho.net/pg_comparator/>`_.  Coelho also
explained the technique further in a paper titled "Remote Comparison of Database
Tables" (`http://cri.ensmp.fr/classement/doc/A-375.pdf <http://cri.ensmp.fr/classement/doc/A-375.pdf>`_).

This existing literature mostly addressed how to find the differences between
the tables, not how to resolve them once found.  I needed a tool that would not
only find them efficiently, but would then resolve them.  I first began thinking
about how to improve the technique further with my article
`http://tinyurl.com/mysql-data-diff-algorithm <http://tinyurl.com/mysql-data-diff-algorithm>`_,
where I discussed a number of problems with the Maxia/Coelho "bottom-up"
algorithm.  After writing that article, I began to write this tool.  I wanted to
actually implement their algorithm with some improvements so I was sure I
understood it completely.  I discovered it is not what I thought it was, and is
considerably more complex than it appeared to me at first.  Fabien Coelho was
kind enough to address some questions over email.

The first versions of this tool implemented a version of the Coelho/Maxia
algorithm, which I called "bottom-up", and my own, which I called "top-down."
Those algorithms are considerably more complex than the current algorithms and
I have removed them from this tool, and may add them back later.  The
improvements to the bottom-up algorithm are my original work, as is the
top-down algorithm.  The techniques to actually resolve the differences are
also my own work.

Another tool that can synchronize tables is the SQLyog Job Agent from webyog.
Thanks to Rohit Nadhani, SJA's author, for the conversations about the general
techniques.  There is a comparison of pt-table-sync and SJA at
`http://tinyurl.com/maatkit-vs-sqlyog <http://tinyurl.com/maatkit-vs-sqlyog>`_

Thanks to the following people and organizations for helping in many ways:

The Rimm-Kaufman Group `http://www.rimmkaufman.com/ <http://www.rimmkaufman.com/>`_,
MySQL AB `http://www.mysql.com/ <http://www.mysql.com/>`_,
Blue Ridge InternetWorks `http://www.briworks.com/ <http://www.briworks.com/>`_,
Percona `http://www.percona.com/ <http://www.percona.com/>`_,
Fabien Coelho,
Giuseppe Maxia and others at MySQL AB,
Kristian Koehntopp (MySQL AB),
Rohit Nadhani (WebYog),
The helpful monks at Perlmonks,
And others too numerous to mention.


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

