
###################
pt-variable-advisor
###################

.. highlight:: perl


****
NAME
****


pt-variable-advisor - Analyze MySQL variables and advise on possible problems.


********
SYNOPSIS
********


Usage: pt-variable-advisor [OPTION...] [DSN]

pt-variable-advisor analyzes variables and advises on possible problems.

Get SHOW VARIABLES from localhost:


.. code-block:: perl

   pt-variable-advisor localhost


Get SHOW VARIABLES output saved in vars.txt:


.. code-block:: perl

   pt-variable-advisor --source-of-variables vars.txt



*****
RISKS
*****


The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

pt-variable-advisor reads MySQL's configuration and examines it and is thus
very low risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
`http://www.percona.com/bugs/pt-variable-advisor <http://www.percona.com/bugs/pt-variable-advisor>`_.

See also "BUGS" for more information on filing bugs and getting help.


***********
DESCRIPTION
***********


pt-variable-advisor examines \ ``SHOW VARIABLES``\  for bad values and settings
according to the "RULES" described below.  It reports on variables that
match the rules, so you can find bad settings in your MySQL server.

At the time of this release, pt-variable-advisor only examples
\ ``SHOW VARIABLES``\ , but other input sources are planned like \ ``SHOW STATUS``\ 
and \ ``SHOW SLAVE STATUS``\ .


*****
RULES
*****


These are the rules that pt-variable-advisor will apply to SHOW VARIABLES.
Each rule has three parts: an ID, a severity, and a description.

The rule's ID is a short, unique name for the rule.  It usually relates
to the variable that the rule examines.  If a variable is examined by
several rules, then the rules' IDs are numbered like "-1", "-2", "-N".

The rule's severity is an indication of how important it is that this
rule matched a query.  We use NOTE, WARN, and CRIT to denote these
levels.

The rule's description is a textual, human-readable explanation of
what it means when a variable matches this rule.  Depending on the
verbosity of the report you generate, you will see more of the text in
the description.  By default, you'll see only the first sentence,
which is sort of a terse synopsis of the rule's meaning.  At a higher
verbosity, you'll see subsequent sentences.


auto_increment
 
 severity: note
 
 Are you trying to write to more than one server in a dual-master or
 ring replication configuration?  This is potentially very dangerous and in
 most cases is a serious mistake.  Most people's reasons for doing this are
 actually not valid at all.
 


concurrent_insert
 
 severity: note
 
 Holes (spaces left by deletes) in MyISAM tables might never be
 reused.
 


connect_timeout
 
 severity: note
 
 A large value of this setting can create a denial of service
 vulnerability.
 


debug
 
 severity: crit
 
 Servers built with debugging capability should not be used in
 production because of the large performance impact.
 


delay_key_write
 
 severity: warn
 
 MyISAM index blocks are never flushed until necessary.  If there is
 a server crash, data corruption on MyISAM tables can be much worse than
 usual.
 


flush
 
 severity: warn
 
 This option might decrease performance greatly.
 


flush_time
 
 severity: warn
 
 This option might decrease performance greatly.
 


have_bdb
 
 severity: note
 
 The BDB engine is deprecated.  If you aren't using it, you should
 disable it with the skip_bdb option.
 


init_connect
 
 severity: note
 
 The init_connect option is enabled on this server.
 


init_file
 
 severity: note
 
 The init_file option is enabled on this server.
 


init_slave
 
 severity: note
 
 The init_slave option is enabled on this server.
 


innodb_additional_mem_pool_size
 
 severity: warn
 
 This variable generally doesn't need to be larger than 20MB.
 


innodb_buffer_pool_size
 
 severity: warn
 
 The InnoDB buffer pool size is unconfigured.  In a production
 environment it should always be configured explicitly, and the default
 10MB size is not good.
 


innodb_checksums
 
 severity: warn
 
 InnoDB checksums are disabled.  Your data is not protected from
 hardware corruption or other errors!
 


innodb_doublewrite
 
 severity: warn
 
 InnoDB doublewrite is disabled.  Unless you use a filesystem that
 protects against partial page writes, your data is not safe!
 


innodb_fast_shutdown
 
 severity: warn
 
 InnoDB's shutdown behavior is not the default.  This can lead to
 poor performance, or the need to perform crash recovery upon startup.
 


innodb_flush_log_at_trx_commit-1
 
 severity: warn
 
 InnoDB is not configured in strictly ACID mode.  If there
 is a crash, some transactions can be lost.
 


innodb_flush_log_at_trx_commit-2
 
 severity: warn
 
 Setting innodb_flush_log_at_trx_commit to 0 has no performance
 benefits over setting it to 2, and more types of data loss are possible.
 If you are trying to change it from 1 for performance reasons, you should
 set it to 2 instead of 0.
 


innodb_force_recovery
 
 severity: warn
 
 InnoDB is in forced recovery mode!  This should be used only
 temporarily when recovering from data corruption or other bugs, not for
 normal usage.
 


innodb_lock_wait_timeout
 
 severity: warn
 
 This option has an unusually long value, which can cause
 system overload if locks are not being released.
 


innodb_log_buffer_size
 
 severity: warn
 
 The InnoDB log buffer size generally should not be set larger than
 16MB.  If you are doing large BLOB operations, InnoDB is not really a good
 choice of engines anyway.
 


innodb_log_file_size
 
 severity: warn
 
 The InnoDB log file size is set to its default value, which is not
 usable on production systems.
 


innodb_max_dirty_pages_pct
 
 severity: note
 
 The innodb_max_dirty_pages_pct is lower than the default.  This can
 cause overly aggressive flushing and add load to the I/O system.
 


flush_time
 
 severity: warn
 
 This setting is likely to cause very bad performance every
 flush_time seconds.
 


key_buffer_size
 
 severity: warn
 
 The key buffer size is unconfigured.  In a production
 environment it should always be configured explicitly, and the default
 8MB size is not good.
 


large_pages
 
 severity: note
 
 Large pages are enabled.
 


locked_in_memory
 
 severity: note
 
 The server is locked in memory with --memlock.
 


log_warnings-1
 
 severity: note
 
 Log_warnings is disabled, so unusual events such as statements
 unsafe for replication and aborted connections will not be logged to the
 error log.
 


log_warnings-2
 
 severity: note
 
 Log_warnings must be set greater than 1 to log unusual events such
 as aborted connections.
 


low_priority_updates
 
 severity: note
 
 The server is running with non-default lock priority for updates.
 This could cause update queries to wait unexpectedly for read queries.
 


max_binlog_size
 
 severity: note
 
 The max_binlog_size is smaller than the default of 1GB.
 


max_connect_errors
 
 severity: note
 
 max_connect_errors should probably be set as large as your platform
 allows.
 


max_connections
 
 severity: warn
 
 If the server ever really has more than a thousand threads running,
 then the system is likely to spend more time scheduling threads than
 really doing useful work.  This variable's value should be considered in
 light of your workload.
 


myisam_repair_threads
 
 severity: note
 
 myisam_repair_threads > 1 enables multi-threaded repair, which is
 relatively untested and is still listed as beta-quality code in the
 official documentation.
 


old_passwords
 
 severity: warn
 
 Old-style passwords are insecure.  They are sent in plain text
 across the wire.
 


optimizer_prune_level
 
 severity: warn
 
 The optimizer will use an exhaustive search when planning complex
 queries, which can cause the planning process to take a long time.
 


port
 
 severity: note
 
 The server is listening on a non-default port.
 


query_cache_size-1
 
 severity: note
 
 The query cache does not scale to large sizes and can cause unstable
 performance when larger than 128MB, especially on multi-core machines.
 


query_cache_size-2
 
 severity: warn
 
 The query cache can cause severe performance problems when it is
 larger than 256MB, especially on multi-core machines.
 


read_buffer_size-1
 
 severity: note
 
 The read_buffer_size variable should generally be left at its
 default unless an expert determines it is necessary to change it.
 


read_buffer_size-2
 
 severity: warn
 
 The read_buffer_size variable should not be larger than 8MB.  It
 should generally be left at its default unless an expert determines it is
 necessary to change it.  Making it larger than 2MB can hurt performance
 significantly, and can make the server crash, swap to death, or just
 become extremely unstable.
 


read_rnd_buffer_size-1
 
 severity: note
 
 The read_rnd_buffer_size variable should generally be left at its
 default unless an expert determines it is necessary to change it.
 


read_rnd_buffer_size-2
 
 severity: warn
 
 The read_rnd_buffer_size variable should not be larger than 4M.  It
 should generally be left at its default unless an expert determines it is
 necessary to change it.
 


relay_log_space_limit
 
 severity: warn
 
 Setting relay_log_space_limit is relatively rare, and could cause
 an increased risk of previously unknown bugs in replication.
 


slave_net_timeout
 
 severity: warn
 
 This variable is set too high.  This is too long to wait before
 noticing that the connection to the master has failed and retrying.  This
 should probably be set to 60 seconds or less.  It is also a good idea to
 use pt-heartbeat to ensure that the connection does not appear to time out
 when the master is simply idle.
 


slave_skip_errors
 
 severity: crit
 
 You should not set this option.  If replication is having errors,
 you need to find and resolve the cause of that; it is likely that your
 slave's data is different from the master.  You can find out with
 pt-table-checksum.
 


sort_buffer_size-1
 
 severity: note
 
 The sort_buffer_size variable should generally be left at its
 default unless an expert determines it is necessary to change it.
 


sort_buffer_size-2
 
 severity: note
 
 The sort_buffer_size variable should generally be left at its
 default unless an expert determines it is necessary to change it.  Making
 it larger than a few MB can hurt performance significantly, and can make
 the server crash, swap to death, or just become extremely unstable.
 


sql_notes
 
 severity: note
 
 This server is configured not to log Note level warnings to the
 error log.
 


sync_frm
 
 severity: warn
 
 It is best to set sync_frm so that .frm files are flushed safely to
 disk in case of a server crash.
 


tx_isolation-1
 
 severity: note
 
 This server's transaction isolation level is non-default.
 


tx_isolation-2
 
 severity: warn
 
 Most applications should use the default REPEATABLE-READ transaction
 isolation level, or in a few cases READ-COMMITTED.
 


expire_log_days
 
 severity: warn
 
 Binary logs are enabled, but automatic purging is not enabled.  If
 you do not purge binary logs, your disk will fill up.  If you delete
 binary logs externally to MySQL, you will cause unwanted behaviors.
 Always ask MySQL to purge obsolete logs, never delete them externally.
 


innodb_file_io_threads
 
 severity: note
 
 This option is useless except on Windows.
 


innodb_data_file_path
 
 severity: note
 
 Auto-extending InnoDB files can consume a lot of disk space that is
 very difficult to reclaim later.  Some people prefer to set
 innodb_file_per_table and allocate a fixed-size file for ibdata1.
 


innodb_flush_method
 
 severity: note
 
 Most production database servers that use InnoDB should set
 innodb_flush_method to O_DIRECT to avoid double-buffering, unless the I/O
 system is very low performance.
 


innodb_locks_unsafe_for_binlog
 
 severity: warn
 
 This option makes point-in-time recovery from binary logs, and
 replication, untrustworthy if statement-based logging is used.
 


innodb_support_xa
 
 severity: warn
 
 MySQL's internal XA transaction support between InnoDB and the
 binary log is disabled.  The binary log might not match InnoDB's state
 after crash recovery, and replication might drift out of sync due to
 out-of-order statements in the binary log.
 


log_bin
 
 severity: warn
 
 Binary logging is disabled, so point-in-time recovery and
 replication are not possible.
 


log_output
 
 severity: warn
 
 Directing log output to tables has a high performance impact.
 


max_relay_log_size
 
 severity: note
 
 A custom max_relay_log_size is defined.
 


myisam_recover_options
 
 severity: warn
 
 myisam_recover_options should be set to some value such as
 BACKUP,FORCE to ensure that table corruption is noticed.
 


storage_engine
 
 severity: note
 
 The server is using a non-standard storage engine as default.
 


sync_binlog
 
 severity: warn
 
 Binary logging is enabled, but sync_binlog isn't configured so that
 every transaction is flushed to the binary log for durability.
 


tmp_table_size
 
 severity: note
 
 The effective minimum size of in-memory implicit temporary tables
 used internally during query execution is min(tmp_table_size,
 max_heap_table_size), so max_heap_table_size should be at least as large
 as tmp_table_size.
 


old mysql version
 
 severity: warn
 
 These are the recommended minimum version for each major release: 3.23, 4.1.20, 5.0.37, 5.1.30.
 


end-of-life mysql version
 
 severity: note
 
 Every release older than 5.1 is now officially end-of-life.
 



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
 


--config
 
 type: Array
 
 Read this comma-separated list of config files; if specified, this must be the
 first option on the command line.
 


--daemonize
 
 Fork to the background and detach from the shell.  POSIX
 operating systems only.
 


--defaults-file
 
 short form: -F; type: string
 
 Only read mysql options from the given file.  You must give an absolute
 pathname.
 


--help
 
 Show help and exit.
 


--host
 
 short form: -h; type: string
 
 Connect to host.
 


--ignore-rules
 
 type: hash
 
 Ignore these rule IDs.
 
 Specify a comma-separated list of rule IDs (e.g. LIT.001,RES.002,etc.)
 to ignore.
 


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
 


--set-vars
 
 type: string; default: wait_timeout=10000
 
 Set these MySQL variables.  Immediately after connecting to MySQL, this string
 will be appended to SET and executed.
 


--socket
 
 short form: -S; type: string
 
 Socket file to use for connection.
 


--source-of-variables
 
 type: string; default: mysql
 
 Read \ ``SHOW VARIABLES``\  from this source.  Possible values are "mysql", "none"
 or a file name.  If "mysql" is specified then you must also specify a DSN
 on the command line.
 


--user
 
 short form: -u; type: string
 
 User for login if not current user.
 


--verbose
 
 short form: -v; cumulative: yes; default: 1
 
 Increase verbosity of output.  At the default level of verbosity, the
 program prints only the first sentence of each rule's description.  At
 higher levels, the program prints more of the description.
 


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

    PTDEBUG=1 pt-variable-advisor ... > FILE 2>&1


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


For a list of known bugs, see `http://www.percona.com/bugs/pt-variable-advisor <http://www.percona.com/bugs/pt-variable-advisor>`_.

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


Percona Toolkit v0.9.5 released 2011-08-04

