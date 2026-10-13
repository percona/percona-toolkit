.. _pt-mongo-log-explainer-readme:

================================
:program:`pt-mongo-log-explainer`
================================

Filter, aggregate, and summarize **MongoDB** (``mongod`` / ``mongos``) logs—especially **replica set** and **sharded cluster** deployments.

The tool accepts multiple log files in **text** (legacy) or **JSON** (structured logging, MongoDB 4.4+), classifies lines into events, optionally **correlates** related sequences across nodes, **tags anomalies**, and prints a **chronological timeline** (``timeline``) or a **columnar multi-node view** (``list``).

Usage
=====

.. code-block:: bash

   pt-mongo-log-explainer [--config=...] [--since=TIME] [--until=TIME] [-v|-vv] [--no-color]
       [--merge-by-directory] [--skip-merge] [--exclude-regexes=...] [--grep-cmd=PATH]
       [--custom-regexes=...] [--version] [--version-check]
       <command> <paths ...>


Commands available
====================

timeline (recommended)
~~~~~~~~~~~~~~~~~~~~~~~~

Merged chronological timeline (one event per line, or JSON).

.. code-block:: bash

   pt-mongo-log-explainer timeline [flags] <log1> [log2] ...

**Default output format**::

   [timestamp] [node] [host:port] [event_type] [status] [details]

**Examples**

.. code-block:: bash

   pt-mongo-log-explainer timeline /path/node1.log /path/node2.log
   pt-mongo-log-explainer timeline --full-scan --elections --replication *.log
   pt-mongo-log-explainer timeline --errors --highlight-anomalies=true *.log
   pt-mongo-log-explainer timeline --json *.log
   pt-mongo-log-explainer timeline --timezone=America/New_York *.log
   pt-mongo-log-explainer timeline --limit=500 *.log
   pt-mongo-log-explainer timeline --skip-correlate --skip-anomalies *.log

**Category filters** (OR logic; omit all to include every classified event):

``--elections``
   Election, primary/secondary transitions, heartbeats, topology, quorum.

``--replication``
   Initial sync, rollback, oplog, sync source changes, replication lag.

``--errors``
   Auth, network, socket, DNS, connection pool, write concern, fatals.

``--sharding``
   Chunk migration, balancer, generic sharding lines.

``--performance``
   Slow queries, long-running commands, index builds, timeouts.

**Other timeline flags**

``--full-scan``
   Read entire files (no ``grep -P`` pre-filter).

``--json``
   JSON array output.

``--highlight-anomalies`` / ``--highlight-anomalies=true``
   Highlight ``[ANOMALY:...]`` tags (respects global ``--no-color``).

``--timezone=ZONE``
   IANA timezone for timestamps (default ``UTC``).

``--limit=N``
   Max events after filters (``0`` = unlimited).

``--skip-correlate`` / ``--skip-anomalies``
   Disable correlation or anomaly passes.


list
~~~~

Columnar output: one column per log / node slice. Pick **one** of ``--all`` **or** any of the grouped flags below.

.. code-block:: bash

   pt-mongo-log-explainer list { --all | [--states] [--topology] [--events] [--replication] [--cluster] } <paths ...>

**Examples**

.. code-block:: bash

   pt-mongo-log-explainer list --all node1.log node2.log
   pt-mongo-log-explainer list --replication --topology --states *.log
   pt-mongo-log-explainer list --events --topology *.log

``--skip-state-colored-column``
   Do not color idle columns by inferred member state.


whois
~~~~~

Resolve a hostname, IPv4, host:port, or member ``_id`` using the translation database built from logs.

.. code-block:: bash

   pt-mongo-log-explainer whois [--json] [--type { nodename | ip | hostport | _id | auto }] <search> <paths ...>

**Examples**

.. code-block:: bash

   pt-mongo-log-explainer whois 507f1f77bcf86cd799439011 mongo.log
   pt-mongo-log-explainer whois 10.0.0.3 *.log
   pt-mongo-log-explainer whois shard1-primary *.log


ctx
~~~

Dump inferred context (translation DB + per-file contexts) as JSON.

.. code-block:: bash

   pt-mongo-log-explainer ctx <paths ...>


regex-list
~~~~~~~~~~

Print all built-in regex definitions as JSON (for use with ``--exclude-regexes``).

.. code-block:: bash

   pt-mongo-log-explainer regex-list


Global flags (before ``<command>``)
===================================

``--config``
   Toolkit configuration file(s); must be first if specified.

``--since`` / ``--until``
   RFC3339 timestamps; only events inside the window are kept.

``--no-color``
   Strip ANSI color sequences from stderr/stdout helpers.

``-v`` / ``-vv``
   Verbose / debug logging.

``--merge-by-directory`` / ``--skip-merge``
   Control how multi-file logs are merged for identity / columns.

``--exclude-regexes``
   Repeatable; each value removes a regex key (see ``regex-list``).
   Scope: the regex pipeline used by ``list``, ``whois`` and ``ctx``. It does
   not affect ``timeline`` / ``summary``, which use the structured parser.

``--grep-cmd``
   Path to GNU-compatible ``grep`` (default ``grep``). Use ``ggrep`` on macOS when needed.

``--custom-regexes``
   ``PATTERN=message`` pairs separated by ``;`` (optional static message).
   Scope: the regex pipeline used by ``list``, ``whois`` and ``ctx``. Custom
   regexes are not applied to ``timeline`` / ``summary``.

``--version`` / ``--version-check``
   Print version; optionally contact Percona update API.


Example outputs
===============

.. code-block:: text

   [2026-04-22 10:15:32] [node1] [10.0.0.1:27017] [ELECTION_SUCCESS] [SUCCESS] [term=5]
   [ANOMALY:ELECTION_STORM] [2026-04-22 10:16:01] [node1] [10.0.0.1:27017] [ELECTION] [INFO] [rs=rs0]


Event Type Reference
====================

Node / Instance
~~~~~~~~~~~~~~~

==============================  ======================  ======================================================
Event Type                      Category                Description
==============================  ======================  ======================================================
``PROCESS_START``               node                    MongoDB process startup (mongod or mongos)
``PROCESS_SHUTDOWN``            failure                 Graceful or forced shutdown
``NODE_LISTEN``                 node                    Listening for connections on port
==============================  ======================  ======================================================

Replica Set Role & Status
~~~~~~~~~~~~~~~~~~~~~~~~~~~

==============================  ======================  ======================================================
Event Type                      Category                Description
==============================  ======================  ======================================================
``PRIMARY_TRANSITION``          role                    Node became primary
``SECONDARY_TRANSITION``        role                    Node became secondary
``STEPDOWN``                    role                    Primary stepping down
``ELECTION``                    role                    Election event (generic)
``ELECTION_SUCCESS``            role                    Election succeeded
``ELECTION_FAIL``               role                    Election failed or aborted
``MEMBER_STATE``                role                    Member state change (PRIMARY, SECONDARY, etc.)
``REPL_STATE``                  role                    Replication state info
==============================  ======================  ======================================================

Cluster Topology
~~~~~~~~~~~~~~~~

==============================  ======================  ======================================================
Event Type                      Category                Description
==============================  ======================  ======================================================
``HEARTBEAT``                   topology                Heartbeat success
``HEARTBEAT_FAIL``              topology                Heartbeat failure / timeout
``MEMBER_JOIN``                 topology                New member added to replica set
``MEMBER_LEAVE``                topology                Member removed from replica set
``MEMBER_UNREACHABLE``          topology                Member marked not reachable / DOWN
``RECONFIG``                    topology                Replica set reconfiguration
``RS_CONFIG``                   topology                Replica set config dump
``RS_INITIATE``                 topology                Replica set initiation
``QUORUM_LOSS``                 topology                Not enough members for majority
``QUORUM_OK``                   topology                Quorum check succeeded
==============================  ======================  ======================================================

Replication Events
~~~~~~~~~~~~~~~~~~

==============================  ======================  ======================================================
Event Type                      Category                Description
==============================  ======================  ======================================================
``INITIAL_SYNC``                replication             Initial sync start / complete / failure
``ROLLBACK``                    replication             Rollback in progress
``REPL_OPLOG``                  replication             Oplog apply / repl writer activity
``REPL_LAG``                    replication             Replication lag measurement
``SYNC_SOURCE_CHANGE``          replication             Oplog sync source changed
``OPLOG_WINDOW``                replication             Oplog window shrinking warning
``OPLOG_TAIL_SLOW``             replication             Slow oplog tailing
``REPL``                        replication             Generic replication event (REPL component fallback)
==============================  ======================  ======================================================

Failures & Errors
~~~~~~~~~~~~~~~~~

==============================  ======================  ======================================================
Event Type                      Category                Description
==============================  ======================  ======================================================
``NETWORK_ERROR``               failure                 Generic network error / connection closed
``AUTH_FAILURE``                failure                 Authentication failure
``FATAL_ERROR``                 failure                 Fatal assertion or crash
``CONN_POOL_ERROR``             failure                 Connection pool exhaustion
``SOCKET_ERROR``                failure                 Socket exception
``DNS_ERROR``                   failure                 DNS resolution failure
``WRITE_CONCERN_ERROR``         failure                 Write concern timeout or error
==============================  ======================  ======================================================

Sharding Events
~~~~~~~~~~~~~~~~

==============================  ======================  ======================================================
Event Type                      Category                Description
==============================  ======================  ======================================================
``CHUNK_MIGRATION``             sharding                Chunk migration (phase=start/complete/abort)
``BALANCER``                    sharding                Balancer activity (enabled/disabled/round)
``SHARDING``                    sharding                Generic sharding event (component fallback)
==============================  ======================  ======================================================

Performance
~~~~~~~~~~~~~

==============================  ======================  ======================================================
Event Type                      Category                Description
==============================  ======================  ======================================================
``SLOW_QUERY``                  performance             Slow query detected
``SLOW_WRITE``                  performance             Slow write operation
``LONG_RUNNING_CMD``            performance             Command exceeding time threshold
``INDEX_BUILD``                 performance             Index build start / complete
``OP_TIMEOUT``                  performance             Operation exceeded MaxTimeMS
``CURSOR_TIMEOUT``              performance             Cursor timed out
==============================  ======================  ======================================================


Anomaly Detection
=================

The tool automatically flags anomalous patterns with ``[ANOMALY:TAG]`` markers.

==============================  ======================================================
Anomaly Tag                     Trigger
==============================  ======================================================
``ROLLBACK``                    Any rollback event
``LAG``                         Replication lag detected
``LAG_SPIKE``                   Numeric lag > 10 seconds
``ELECTION_STORM``              3+ elections within 5 minutes
``FREQUENT_ELECTIONS``          4+ elections within 15 minutes
``TOPOLOGY_FLAP``               5+ member join/leave events in 30 minutes
``NODE_FLAPPING``               3+ restart cycles (shutdown+start) in 30 minutes
``SYNC_FAILURE``                Initial sync or other sync failure
``SYNC_TIMEOUT``                Initial sync start without completion in 2 hours
``AUTH_BURST``                  5+ auth failures from same node in 1 minute
``SUSTAINED_HB_FAIL``           3+ heartbeat failures within 30 seconds
==============================  ======================================================


Event Correlation
=================

The correlator detects cross-node causal sequences and annotates event details
with ``sequence=`` tags:

- **heartbeat_loss -> election**: Heartbeat failure followed by election within 3 minutes
- **stepdown -> election -> primary**: Stepdown chain with new primary within 30 seconds
- **initial_sync_lifecycle**: Initial sync start matched with its completion/failure
- **restart**: Process shutdown followed by start on the same node within 10 minutes
- **rollback -> recovery**: Rollback followed by oplog catch-up on the same node
- **migration lifecycle**: Chunk migration start matched with complete/abort

Related events share a ``sequence_id`` field in JSON output for programmatic grouping.


JSON Output Schema
==================

When using ``timeline --json``, each event is a JSON object::

   {
     "time": "2026-04-20T10:00:06Z",
     "node": "mongo-primary",
     "host_port": "10.0.0.1:27017",
     "event_type": "ELECTION_SUCCESS",
     "status": "SUCCESS",
     "details": "term=1 newState=PRIMARY",
     "category": "role",
     "source_file": "/path/to/node1.log",
     "raw": "<original log line>",
     "anomaly": "ELECTION_STORM",
     "sequence_id": "stepdown-3"
   }

Fields ``raw``, ``anomaly``, and ``sequence_id`` are omitted when empty.


Sphinx / HTML documentation
===========================

A Percona-style page suitable for the Toolkit docs tree lives at:

``docs/pt-mongo-log-explainer.rst`` (repository root).


Requirements
============

* ``grep`` with **PCRE** support (``grep -P``), version 3.x typical on Linux.
* On macOS, set ``--grep-cmd=ggrep`` if BSD grep is the default.

Building
========

From the Go module (see the main Percona Toolkit Makefile under ``src/go``):

.. code-block:: bash

   VERSION=0.0.1 make build

This produces ``bin/pt-mongo-log-explainer`` when run from repository conventions.
