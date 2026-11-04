.. pt-mongodb-summary:

=============================
:program:`pt-mongodb-summary`
=============================

``pt-mongodb-summary`` collects information about a MongoDB cluster.
It collects information from several sources
to provide an overview of the cluster.

Usage
=====

.. code-block:: bash

   pt-mongodb-summary [--config FILE[,FILE...]] [OPTIONS] [HOST[:PORT]]

By default, if you run ``pt-mongodb-summary`` without any parameters,
it will try to connect to ``localhost`` on port ``27017``.
Options can also be read from configuration files (see ``--config``).
The program collects information about MongoDB instances
by running administration commands and formatting the output.

Run it against a **mongos** for the cluster sections (Shards, Cluster wide,
Balancer) and the oplog of every replica set, and against a **mongod**
for the details of that node (WiredTiger, startup warnings, its own startup
options).

Required privileges
-------------------

The built-in ``clusterMonitor`` role is enough for every section except
the legacy **Cluster wide** section on mongos, which needs more:
``collStats`` on config system collections such as ``config.system.preimages``
is denied to ``clusterMonitor``, so that section is listed under **Not collected**.
Three values need more and are printed as
``not readable with this login`` instead:

* user and role counts in **Security**
  (``find`` on ``admin.system.users`` and ``admin.system.roles``,
  for example ``userAdminAnyDatabase``);
* the change stream pre/post image expiration on MongoDB 6.0 and 7.x
  (``getClusterParameter``, granted by ``clusterManager``);
* the oplog of a member the login cannot read (shown in that member's row).

With a custom role that lacks something ``clusterMonitor`` grants,
the sections that could not be read are listed under **Not collected**
with the missing action, and the report is still printed with exit code 0.

Without ``--username`` against a server that has authentication enabled,
the tool stops with exit code 3 and
``authentication required: pass --username/--password (and --authenticationDatabase)``.

If the server cannot be reached or the login fails, the tool stops with
exit code 5 and names the likely cause: wrong credentials, a TLS mismatch,
nothing listening on the port, or a host name that cannot be resolved.

Arbiters accept no logins: the driver does not log in to an arbiter, and the
credentials are used only for the other members. On the arbiter host,
through ``localhost``, the report shows
This host, the command line, Startup Options, Running Ops, WiredTiger,
Memory, Connections and Security (without user and role counts).
Through any other address the arbiter answers only ``isMaster``: the report
shows This host and the Oplog members, and **Not collected** says to run
the tool on the arbiter host. Host facts, startup warnings, user and role
counts, FCV, profiler settings, database inventory, mongos and oplog details
are never read from an arbiter. FCV is not shown there because an arbiter
reports the newest FCV of its binary, not the FCV of the replica set.

Time limit
----------

A run takes at most 23 seconds plus the sampling time
(``--running-ops-samples`` x ``--running-ops-interval``, 5 seconds by default).
Every server call has its own deadline within that limit:
5 seconds for single calls, 10 seconds for the whole member phase
(Instances and Oplog), 5 seconds each for the database pass and the TTL index walk
of Database Inventory. Whatever was collected is printed, and every part that
was not reached is listed as ``timed out`` under **Not collected**.

Options
-------

``-a``, ``--authenticationDatabase``
  Specifies the database used to establish credentials and privileges
  with a MongoDB server.
  By default, the ``authSource`` or the database of ``--uri`` is used,
  else ``admin``.
  The option is ignored for mechanisms that authenticate against
  ``$external`` (``GSSAPI``, ``MONGODB-X509``, ``PLAIN``, ``MONGODB-AWS``,
  ``MONGODB-OIDC``).

``-c``, ``--no-version-check``
  Do not check for a newer version of ``pt-mongodb-summary``.

``--config``
  Comma-separated list of configuration files to read. It must be the first
  option and takes no equal sign: ``--config /path/a.conf,/path/b.conf``.
  Without it, the tool reads ``/etc/percona-toolkit/percona-toolkit.conf``,
  ``/etc/percona-toolkit/pt-mongodb-summary.conf``,
  ``$HOME/.percona-toolkit.conf`` and ``$HOME/.pt-mongodb-summary.conf``
  if they exist. ``--config ''`` reads no file.
  Each line is ``option=value``, or just ``option`` for a flag
  (for example ``no-version-check``), using the long option names.

``-f``, ``--output-format``
  Specifies the report output format. Valid options are: ``text``, ``json``.
  The default value is ``text``.

``-h``, ``--help``
  Show help message and exit.

``--host``
  Specifies the hostname or IP address of the MongoDB server to connect to.

``-i``, ``--running-ops-interval``
  Interval in milliseconds to wait between samples of running operations.
  Default: 1000 milliseconds.

``-l``, ``--log-level``
  Specifies the logging level. Valid options: ``panic``, ``fatal``, ``error``,
  ``warn``, ``info``, ``debug``.
  Default: ``warn``.
  Parts that could not be read are logged at ``warn`` when the login should
  have been able to read them (network errors, timeouts, missing
  ``clusterMonitor`` privileges) and at ``info`` when that is expected
  (arbiters, member states, privileges ``clusterMonitor`` does not have).
  ``debug`` also logs how long each stage took.
  An invalid value stops the tool with exit code 2.

``-p``, ``--password``
  Specifies the password to use when connecting to a server
  with authentication enabled.

  If you specify the option without a value as the last argument
  (``-p`` or ``--password`` with no host after it),
  ``pt-mongodb-summary`` asks for the password interactively.

``--port``
  Specifies the port of the MongoDB server to connect to.

``-s``, ``--running-ops-samples``
  Number of samples to collect for running operations.
  Default: 5. With ``0``, Running Ops is not shown and WiredTiger shows
  only the cache sizes.

``--sslCAFile``
  Path to the SSL CA certificate file used for authentication.

``--sslPEMKeyFile``
  Path to the SSL client PEM file used for authentication.

``--uri``
  Full MongoDB URI describing hosts and options.
  Command-line flags have higher priority than URI settings.
  If a full URI is provided, you cannot also specify ``--host`` or ``--port``.
  Example: ``mongodb://admin:secret@localhost:27017``

``-u``, ``--username``
  Specifies the username to use when connecting to a server
  with authentication enabled.

``-v``, ``--version``
  Show version information and exit.

Output example
==============

.. code-block:: none

   # Instances ##############################################################################################
     PID  Host             Type                ReplSet  Engine      Priority  Votes
       1  localhost:37018  PRIMARY             rs       wiredTiger         2      1
       1  localhost:37019  SECONDARY           rs       wiredTiger         1      1
          localhost:37020  ARBITER             rs                          0      1
       1  localhost:37021  SECONDARY (hidden)  rs       wiredTiger         0      0

   # This host
   # Report On db-host:37018 ########################################
                   PID Owner | mongod
                    Hostname | db-host:37018
                     Version | 7.0.45-24
                         FCV | 7.0
                    Built On | Linux x86_64
                     Started | 2026-11-03 19:54:38 UTC
                     Datadir | /data/db
                Process Type | PRIMARY
                     ReplSet | rs
                 Repl Status |

   # OS & Production Checks #################################################################################
                          OS | Red Hat Enterprise Linux release 9.8 (Plow)
                      Kernel | 7.2.11-200.fc44.x86_64
                   CPU cores | 12
                         RAM | 15786 MB
                        NUMA | off or interleaved
            Open files limit | 1024  [WARNING: below 64000]
                Local checks | skipped: argv differs
            Startup warnings | 1
     - Soft rlimits for open file descriptors too low {"currentValue":1024,"recommendedMinimum":64000}

   # Command line arguments
   mongod --replSet rs --keyFile /tmp/key --bind_ip 127.0.0.1 --port 37018 --dbpath /data/db

   # Startup Options ########################################################################################
     net.bindIp          = 127.0.0.1
     net.port            = 37018
     replication.replSet = rs
     security.keyFile    = /tmp/key
     storage.dbPath      = /data/db

   # Running Ops ############################################################################################
   Per second over 5.0s of sampling; "Since start" = average over 12h 42m of uptime
   Type           Min/s       Max/s       Avg/s   Since start/day
   Insert             0           0           0              9.45
   Query              0           0           0             455.6
   Update             0           0           0              94.5
   Delete             0           0           0             370.5
   GetMore            0        2.00        0.40             26112
   Command         1.00        6.01        4.00            355760

   # WiredTiger #############################################################################################
              Storage Engine | wiredTiger
                  Cache Size | 7.21 GB
                  Cache Used | 1.25 MB (0.0%)
                  Cache Free | 7.21 GB (100.0%)
                 Cache Dirty | 993.93 KB (0.0%)
               Cache Updates | 1.22 MB (0.0%)
                 Rate Window | 5.0s
             Read Into Cache | 0 pages/s, 0.00 bytes/s uncompressed
          Written From Cache | 0 pages/s, 0.00 bytes/s uncompressed
    Unmodified Pages Evicted | 0/s
      Modified Pages Evicted | 0/s
   App Thread Evict Attempts | 0/s
    App Thread Wait on Cache | 0 ms/s

   # Memory #################################################################################################
          Resident Set (RSS) | 61.00 MB
          TCMalloc Allocated | 117.52 MB
               TCMalloc Free | 20.94 MB (15.1% of allocated + free)
     TCMalloc Released to OS | 368.00 KB

   # Connections & Profiling ################################################################################
                     Current | 21
                   Available | 388
                       Limit | 409 (current + available)
      maxIncomingConnections | not set
                      Active | 6
                    Rejected | 0
               Total Created | 645
           Slow Op Threshold | 50 ms (startup: 100 ms)
                 Sample Rate | 1

   # Security ###############################################################################################
   Users  : not readable with this login (needs find on admin.system.users)
   Roles  : not readable with this login
   Auth   : enabled
   SSL    : disabled
   Port   : 37018
   Bind IP: 127.0.0.1

   # Oplog ##################################################################################################
                 Replica Set | rs
                     Primary | localhost:37018
               Last Election | 2026-11-03 19:55:03 UTC (priorityTakeover)
     Host             State      Max MB  Used MB  Used%       Window  Last Entry (UTC)
     localhost:37018  PRIMARY      5934        0   0.0%  12.69 hours  2026-11-04 08:36:15
     localhost:37019  SECONDARY    5934        0   0.0%  12.69 hours  2026-11-04 08:36:15
     localhost:37020  ARBITER    no oplog on an arbiter
     localhost:37021  SECONDARY    5934        0   0.0%  12.69 hours  2026-11-04 08:36:15
             Shortest Window | localhost:37018 (12.69 hours)
              Longest Window | localhost:37021 (12.69 hours)

   # Change Streams #########################################################################################
      Pre/Post Images Expire | not readable with this login (needs getClusterParameter: clusterManager)

   # Database Inventory #####################################################################################
     Database   Colls  Views  Indexes  TTL Idx  Documents          Data    Storage   Idx Size
     testdb         2      1        4        1          2  243.00 bytes   60.00 KB  108.00 KB
     other          1      0        2        1          1   29.00 bytes   20.00 KB   40.00 KB
     Total (2)      3      1        6        2          3  272.00 bytes   80.00 KB  148.00 KB
     admin          3      0        4      n/a          6       1.29 KB   76.00 KB   96.00 KB
     config        11      0       18      n/a          0    0.00 bytes  128.00 KB  168.00 KB
     local         10      1        9      n/a       4679     501.58 KB  448.00 KB  180.00 KB

Sections
--------

A section is printed only when it applies to the node and has data.
Sections appear in this order:

* **Mongos**

  The routers that pinged the cluster in the last 5 minutes, from
  ``config.mongos``. Shown on mongos and on config server members.

* **Shards**

  ``listShards``, sorted by name, with draining state and zones.
  Shown on mongos only.

* **Instances**

  The members of every replica set, from ``replSetGetStatus``
  on each member (through ``getShardMap`` on mongos).
  PID and engine come from each member's own ``serverStatus`` and stay empty
  for members that could not be read, such as arbiters and unreachable members.
  Type adds ``(hidden)`` and ``(delayed N s)``, and ``SHARDSVR/`` or ``CONFIGSVR/``
  on shard and config server members.
  Priority and Votes come from ``replSetGetConfig``.
  Members that could not be read keep the state seen by the oplog discovery.
  ``no replica sets found`` is printed only for a standalone server.

* **This host**

  Version, FCV (``getParameter``), build, start time (server time
  minus uptime, in UTC), data directory, role and replica set,
  from ``isMaster``, ``hostInfo``, ``getCmdLineOpts`` and ``serverStatus``.
  The executable path, its user and the number of local ``mongod`` processes
  are shown only when the tool runs on the same host as the server
  (see `Local checks`_). On arbiters a notice explains what is not collected.
  Process Type is the member's role as in **Instances** (from ``replSetGetStatus``
  and ``replSetGetConfig``), for example ``PRIMARY``,
  ``SECONDARY (hidden)``, ``SHARDSVR/PRIMARY`` or ``ARBITER``; mongos and a
  standalone server show ``mongos`` and ``mongod``.

* **OS & Production Checks**

  OS, kernel, CPU cores and CPU affinity, RAM and its limit (no limit means
  none was detected), NUMA and the open files limit (warning below 64000)
  from ``hostInfo``, and the startup warnings of the server
  (``getLog: "startupWarnings"``). The startup warnings reflect the state
  when the server started. On the server host the section also checks
  ``vm.max_map_count`` (warning below 2 x the connection limit),
  the soft ``Max processes`` limit of ``mongod`` (warning below 64000 unless it
  runs as root) and the lowest cgroup ``pids.max`` (warning below 64000);
  otherwise it prints ``Local checks | skipped: <reason>``.

* **Command line arguments**

  The arguments the server was started with (``getCmdLineOpts``).
  Values of options whose name ends in ``password``, ``passwd``, ``secret``
  or ``token`` are printed as ``<password>``.

* **Startup Options**

  Every option the server parsed at startup (``getCmdLineOpts``),
  as dotted names in server order, masked like the command line.
  Values longer than 200 characters are cut in the text output.
  These are startup values; the effective cache size, slow operation
  threshold and TLS mode are shown in their own sections.

* **Running Ops**

  Operation rates over the sampling window: ``serverStatus`` is read
  ``--running-ops-samples`` times, ``--running-ops-interval`` apart.
  Min/s and Max/s are the quietest and busiest interval, Avg/s is the total
  change over the total time, all measured with the server's own uptime.
  ``Since start/day`` is the counter divided by the uptime, per day.
  The tool's own ``serverStatus`` calls count as commands.
  On secondaries, or when they changed, the ``Replicated`` rows show
  ``opcountersRepl``, which count documents, not operations.
  Intervals across a restart or a host change are skipped; if a sample fails
  after usable intervals, a ``partial:`` line says how many were used.

* **WiredTiger**

  Effective cache size, used, free, dirty and update bytes from ``serverStatus``,
  and page, byte (uncompressed) and eviction rates plus the time application
  threads waited for the cache over the sampling window (no rates for windows
  under 1 second). ``1000 ms/s`` of cache wait means one thread waited
  for the whole window. Not shown on mongos or other storage engines.

* **Memory**

  Resident memory and TCMalloc allocated, free (page heap plus cache
  free lists) and released bytes from ``serverStatus``.

* **Connections & Profiling**

  Current, available and active connections, the connection limit
  (current + available), rejected (7.0 and later) and total created connections from
  ``serverStatus``, and the global slow operation threshold and sample rate
  (``profile: -1`` on ``admin``) with the startup threshold when it differs.

* **Security**

  User and role counts, authentication (``enabled``, ``disabled`` or
  ``not enforced (transitionToAuth)``), the TLS mode (``getParameter tlsMode``,
  else the startup options), port and bind addresses, from ``getCmdLineOpts``.
  Bind address warnings are shown only on the server host.

* **Oplog**

  One table per replica set: every member with its oplog size limit, used
  size and percentage (may exceed 100%), time window and last entry, plus the
  primary, the last election and the shortest and longest windows.
  Members that cannot be read show the reason in their row. Hidden members
  are listed when at least one data member of the set answers.
  Users created through mongos exist only on the config servers; reading a
  shard member directly needs a shard-local user.

* **Change Streams**

  Pre/post image expiration and pre-image collection size: from
  ``serverStatus`` on 8.0, from ``getClusterParameter`` on 6.0 and 7.x.
  Replica set members and mongos on 6.0 and later only.

* **Database Inventory**

  For each database: collections, views, indexes, TTL indexes, documents,
  data size (uncompressed), storage and index size, from ``listDatabases``,
  ``dbStats``, ``listCollections`` and ``$indexStats``. User databases come first,
  largest first, then their total, then ``admin``, ``config`` and ``local``.
  TTL indexes are single-field, non-``_id`` indexes with
  ``expireAfterSeconds`` in user databases (``n/a`` for internal ones).
  ``-`` means unknown or not reached within the time limit, ``N+`` is a lower
  bound, and notes under the table explain both. On mongos only user databases
  are listed, sizes are summed over shards and Indexes counts distinct names.
  On shard and config server members only internal databases are listed;
  connect through mongos for per-database statistics. Not shown on arbiters.

* **Cluster wide**

  The number of sharded and unsharded databases, collections, and their size,
  from ``listDatabases`` and ``collStats`` for every collection. Mongos only.

* **Balancer (per day)**

  Chunk moves, splits and drops from ``config.changelog``. Mongos only.

* **Not collected**

  Every section or item the tool tried to read and could not, with the reason.
  Values that are explained in place (``not readable`` lines, oplog rows,
  inventory cells, skipped local checks) are not repeated here,
  nor are the parts that are skipped by design on a node type.

Local checks
------------

Some lines describe the server's host rather than the server:
the executable path and user, the number of ``mongod`` processes,
``vm.max_map_count``, process and cgroup limits, and bind address warnings.
They are shown only when the tool runs next to the server process:
``/proc/<pid>/cmdline`` of the server's PID must match its command line,
the host name must match, and the process start time must match the
server's uptime within 60 seconds. Otherwise the reason is printed:
``not the same host``, ``process not visible (hidepid, other PID namespace or user)``,
``no /proc on this OS``, ``argv differs`` or ``process start time differs``.
Two containers with identical command lines started within 60 seconds of
each other can still be taken for one another.

JSON output
-----------

``--output-format json`` prints the same data with the Go field names as keys.
Values that are unknown are ``null``. New keys: ``OSChecks``, ``StartupOptions``,
``WiredTiger``, ``Memory``, ``Connections``, ``Profiling``, ``ChangeStreams``,
``DatabaseInventory``, ``ShardsInfo``, ``MemberDetails``, and new fields in ``HostInfo``,
``RunningOps``, ``SecuritySettings`` and ``OplogInfo``.
Changes to existing keys:

* ``SecuritySettings.SSL`` holds the TLS mode (it was always ``disabled``
  on 4.2 and later).
* ``HostInfo.CmdlineArgs`` is masked like the command line.
* ``HostInfo.ProcCreateTime`` is the server start time in UTC.
* ``MongosInfo`` is ``null`` except on mongos and config server members.
* ``OplogInfo`` has one entry per member of every replica set; ``[0]`` is still
  the shortest window.
* ``ReplicaMembers`` entries come from ``replSetGetStatus`` as seen by the
  member that reported them. ``ID`` is the member's own PID and
  ``StorageEngine`` its own engine, both empty when the member could not be
  read (``ID`` used to repeat this host's PID). Members known only from
  ``getShardMap`` or ``isMaster`` have ``Health`` and ``State`` ``0``,
  meaning unknown, and only ``StateStr`` carries the member state.
* ``MemberDetails`` lists ``{Host, Priority, Votes, Hidden, DelaySecs}`` for
  every member; ``Priority`` and ``Votes`` are ``null`` when
  ``replSetGetConfig`` could not be read.
* ``Errors`` lists ``{Section, Item, Code, Reason}`` objects for
  **Not collected**.
* ``RunningOps.Insert`` ... ``Command`` keep ``Min``, ``Max``, ``Total``
  (per-interval changes) and ``Avg`` (equal to ``Total``); the rates are in
  ``RunningOps.Rates``.

Exit codes
----------

=====  ==========================================================
Code   Meaning
=====  ==========================================================
0      The report was printed, even with sections not collected
1      The results could not be formatted
2      The command line could not be parsed
3      The server could not be identified, or a login is required
4      The connection options are invalid
5      The client could not be created, connected or logged in
=====  ==========================================================

Authors
=======

Carlos Salguero

ABOUT PERCONA TOOLKIT
=====================

This tool is part of Percona Toolkit, a collection of advanced command-line
tools for MySQL developed by Percona.  Percona Toolkit was forked from two
projects in June, 2011: Maatkit and Aspersa.  Those projects were created by
Baron Schwartz and primarily developed by him and Daniel Nichter.  Visit
`http://www.percona.com/software/ <http://www.percona.com/software/>`_ to learn about other free, open-source
software from Percona.

COPYRIGHT, LICENSE, AND WARRANTY
================================

This program is copyright 2011-2026 Percona LLC and/or its affiliates.

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

VERSION
=======

:program:`pt-mongodb-summary` 3.7.2

