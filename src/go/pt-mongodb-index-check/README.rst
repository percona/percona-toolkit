.. _pt-mongodb-index-check:

=================================
:program:`pt-mongodb-index-check`
=================================

Performs checks on MongoDB indexes: identifies duplicated (prefix) indexes and
analyzes unused indexes with a multi-signal scoring system.

Checks available
================

Duplicated indexes
~~~~~~~~~~~~~~~~~~

System databases (``admin``, ``config``, ``local``) and internal collections
whose names start with ``system.`` (for example ``system.profile``) are not
scanned for duplicate prefixes, consistent with the unused-index path.

The sectioned **Duplicate Prefix Index Report** (banner, per-pair reason,
``dropIndex`` action, optional index sizes from ``collStats``, and a separate
block for unique-prefix warnings) is printed in text mode for ``check-duplicates``
and ``check-all`` only; ``check-unused`` output focuses on unused-index analysis.

Check for indexes that are the prefix of other indexes. For example if we have these 2 indexes

.. code-block:: javascript

   db.getSiblingDB("testdb").test_col.createIndex({"f1": 1, "f2": -1, "f3": 1, "f4": 1}, {"name": "idx_01"});
   db.getSiblingDB("testdb").test_col.createIndex({"f1": 1, "f2": -1, "f3": 1}, {"name": "idx_02"});


The index ``idx_02`` is the prefix of ``idx_01`` because it has the same
keys in the same order so, ``idx_02`` can be dropped.

The duplicate check is property-aware: two indexes with the same key prefix are
**not** flagged as duplicates if they differ in any of the following:

- ``partialFilterExpression`` -- indexes covering different document subsets
- ``sparse`` -- sparse and non-sparse indexes have different null-handling behavior
- ``collation`` -- indexes with different collation rules serve different queries

The ``_id_`` index is always excluded from duplicate candidates since it is a
MongoDB requirement and cannot be dropped.

**Index type awareness:** Hashed, text, and geospatial index types (``2dsphere``,
``2d``) are treated as distinct types in the key comparison. An index on
``{_id: 1}`` and ``{_id: "hashed"}`` are never considered prefix duplicates
because they use fundamentally different index structures.

If a **unique** index is detected as a prefix of a non-unique container index,
a warning is emitted because dropping the unique index would remove the
uniqueness constraint.

.. code-block:: text

   WARNING: prefix index enforces unique constraint; dropping requires the container index to also be unique

Unused indexes (enhanced analysis)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The unused index check goes beyond the simple ``$indexStats`` ``accesses.ops = 0``
metric. It uses a multi-signal scoring system that collects data from four sources:

1. **$indexStats** -- read access counts and the stats reset timestamp
2. **listIndexes** -- index properties (unique, sparse, partial, TTL, hidden)
3. **collStats** -- per-index sizes, collection document count, total index size
4. **serverStatus** -- global write rate for cost estimation

Each index is evaluated through a scoring decision tree that produces one of
these recommendations:

+-------------------+--------------------------------------------------------------+
| Recommendation    | Meaning                                                      |
+===================+==============================================================+
| ``SAFE_TO_DROP``  | High confidence the index provides no value; includes a      |
|                   | ``dropIndex`` command ready to copy.                         |
+-------------------+--------------------------------------------------------------+
| ``LIKELY_UNUSED`` | Strong signal of no usage, but low cost to keep (small size) |
+-------------------+--------------------------------------------------------------+
| ``LOW_USAGE``     | Index is used but at a very low rate relative to write cost  |
+-------------------+--------------------------------------------------------------+
| ``MONITOR``       | Insufficient data to decide (warmup period, empty collection)|
+-------------------+--------------------------------------------------------------+
| ``KEEP``          | Index enforces a constraint (unique, TTL) or is hidden       |
+-------------------+--------------------------------------------------------------+

**Hard guards** -- The following indexes are never flagged for removal:

- ``_id_`` (MongoDB requirement)
- Unique indexes (enforce data integrity constraints)
- TTL indexes (provide automatic document expiration)
- Hidden indexes (intentionally excluded from planner by admin)
- Indexes in system databases (admin, config, local)
- Collections whose names begin with ``system.`` (internal collections such as ``system.profile``)

**Warmup period** -- After a ``mongod`` restart, ``accesses.since`` resets and
all indexes appear to have zero ops. The tool waits for the observation window
to exceed ``--warmup-days`` (default: 7) before flagging unused indexes.

**Cross-reference with duplicates** -- When ``check-all`` is used, a prefix-
duplicate index with zero ops whose container index has active reads is
recommended as ``SAFE_TO_DROP`` with an explanation.

Usage
=====

Run the program as ``pt-mongodb-index-check <command> [flags]``

You must specify which databases to check using ``--databases`` or
``--all-databases``. If neither is provided but the connection URI contains a
database name (e.g., ``mongodb://host:port/mydb``), that database is used as
the default.

The tool verifies connectivity (Ping) immediately after connecting and reports
a clear error if the server is unreachable or credentials are invalid. Those
errors are written to standard error; if you paste output from several runs
or from a wrapper that merges streams, a failed authentication line can appear
above a successful report from a different invocation.

Environment
===========

PTDEBUG
~~~~~~~

The environment variable ``PTDEBUG`` enables verbose diagnostic logging on
**standard error**, consistent with other Percona Toolkit tools. Set it to any
non-empty value except ``0`` (for example ``PTDEBUG=1``). Unset or empty turns
debugging off; ``PTDEBUG=0`` is treated as off (same as Perl toolkit
``$ENV{PTDEBUG} || 0``).

The normal report (text templates or ``--json``) is still written to **standard
output** only. To capture everything in one file:

.. code-block:: bash

   PTDEBUG=1 pt-mongodb-index-check check-all --mongodb.uri=mongodb://127.0.0.1:27017 --all-databases --all-collections > report.txt 2>&1

Diagnostic lines intentionally avoid printing raw connection passwords (the
password in ``--mongodb.uri`` is redacted in debug output).

Debug output can grow large on clusters with many databases and collections.

Available commands
~~~~~~~~~~~~~~~~~~

================= ==================================
Command           Description
================= ==================================
check-duplicates  Run checks for duplicated indexes.
check-unused      Run check for unused indexes.
check-all         Run all checks.
================= ==================================

Available flags
~~~~~~~~~~~~~~~

+----------------------------------+------------------------------------------+
| Flag                             | Description                              |
+==================================+==========================================+
| --all-databases                  | Check in all databases excluding         |
|                                  | system dbs.                              |
+----------------------------------+------------------------------------------+
| --databases=DATABASES,...        | Comma separated list of databases to     |
|                                  | check.                                   |
+----------------------------------+------------------------------------------+
| --all-collections                | Check in all collections in the          |
|                                  | selected databases.                      |
+----------------------------------+------------------------------------------+
| --collections=COLLECTIONS,...    | Comma separated list of collections to   |
|                                  | check.                                   |
+----------------------------------+------------------------------------------+
| --mongodb.uri=                   | Connection URI.                          |
+----------------------------------+------------------------------------------+
| --json                           | Show output as JSON.                     |
+----------------------------------+------------------------------------------+
| --warmup-days=7                  | Minimum observation window (days)        |
|                                  | before flagging unused indexes.          |
+----------------------------------+------------------------------------------+
| --low-usage-threshold=1.0        | Ops/day below which an index is          |
|                                  | considered low-usage.                    |
+----------------------------------+------------------------------------------+
| --large-index-size=10485760      | Index size threshold in bytes for        |
|                                  | "large" classification (default 10 MB). |
+----------------------------------+------------------------------------------+
| --include-low-usage              | Also report indexes with low but         |
|                                  | non-zero usage.                          |
+----------------------------------+------------------------------------------+
| --cross-reference-duplicates     | Combine unused + duplicate analysis for  |
|                                  | better recommendations (default: true).  |
+----------------------------------+------------------------------------------+
| --version                        | Show version information.                |
+----------------------------------+------------------------------------------+

Examples
========

Check all indexes across all databases:

.. code-block:: bash

   pt-mongodb-index-check check-all --mongodb.uri=mongodb://127.0.0.1:27017 --all-databases --all-collections

Check a specific database:

.. code-block:: bash

   pt-mongodb-index-check check-unused --mongodb.uri=mongodb://127.0.0.1:27017/mydb --all-collections

Include low-usage indexes with a custom threshold:

.. code-block:: bash

   pt-mongodb-index-check check-unused --mongodb.uri=mongodb://127.0.0.1:27017 --databases=mydb --all-collections --include-low-usage --low-usage-threshold=0.5

Sample output
~~~~~~~~~~~~~

.. code-block:: text

   # ============================================================
   # Duplicate Prefix Index Report
   # ============================================================
   # Pairs found: 1 across 1 database(s), 1 collection(s)
   # ---- REDUNDANT PREFIX (shorter index is candidate to drop) ---
     mydb.orders
       Prefix:    'idx_region' {region:1}  4.0 KB
       Container: 'idx_region_date' {region:1, date:-1}  8.0 KB
       Reason: 'idx_region' is a key-order prefix of 'idx_region_date'; any query served by 'idx_region' can also use 'idx_region_date'.
       Action: db.orders.dropIndex("idx_region")

   # Summary: 1 redundant prefix pair(s), 0 with unique/constraint warning(s)

   # ============================================================
   # Unused Index Analysis
   # ============================================================
   # Observation window: 2024-01-01T00:00:00Z to 2024-02-15T00:00:00Z (45.0 days)
   # Indexes analyzed: 8 across 1 database(s), 3 collection(s)
   # Server write rate: ~2400 ops/sec

   # ---- SAFE TO DROP (high confidence) --------------------------

     mydb.orders  index 'idx_old_status' {status:1, date:-1}
       Ops: 0 in 45 days | Size: 128.0 MB | Score: 0.95
       Reason: Zero reads in 45 days; index is 128.0 MB and costs write amplification
       Action: db.orders.dropIndex("idx_old_status")

   # ---- LIKELY UNUSED (review recommended) ----------------------

     mydb.users  index 'idx_legacy_field' {legacyCode:1}
       Ops: 0 in 45 days | Size: 2.0 MB | Score: 0.80
       Reason: Zero reads in 45 days; small index (2.0 MB), low cost to keep

   # ---- MONITOR (insufficient data) -----------------------------

     mydb.logs  index 'idx_new_feature' {featureFlag:1}
       Ops: 0 in 3 days | Size: 500.0 KB | Score: 0.10
       Reason: Index created/stats reset 3 days ago; re-check after 7 days

   # ---- KEEP (constraints / special) ----------------------------

     mydb.users  index 'email_unique' {email:1}  [UNIQUE]
       Ops: 0 in 45 days | Kept: enforces uniqueness constraint

   # Summary: 1 safe to drop (saving ~128.0 MB), 1 likely unused,
   #           0 low usage, 1 monitoring, 1 kept (constraints)

JSON output includes the full ``IndexAnalysis`` array with all fields
(``score``, ``recommendation``, ``confidence``, ``reason``, ``indexSizeBytes``,
``ageDays``, ``opsPerDay``, etc.) for programmatic consumption.

Edge cases and caveats
======================

accesses.since resets on restart
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The ``accesses.since`` field resets every time ``mongod`` restarts. On clusters
with frequent rolling restarts (e.g., Kubernetes pod recycling), the observation
window may be very short. The tool prints the observation window in the report
header and marks indexes in the warmup period as ``MONITOR``.

Sharded clusters
~~~~~~~~~~~~~~~~

On sharded clusters, ``$indexStats`` returns one entry per shard per index. The
tool automatically aggregates these entries by index name: it sums
``accesses.ops`` across all shards and uses the oldest ``accesses.since`` as the
observation window (most conservative). This produces one row per index in the
report instead of N rows for N shards.

When a row omits the top-level ``name`` field but includes ``spec.name`` (seen on
some mongos responses), the tool normalizes the document before aggregation so
shards still group under the same index name.

Per-shard detail is still available via ``--json`` output, which includes the
shard count for each aggregated entry.

Read preference routing
~~~~~~~~~~~~~~~~~~~~~~~

Applications using ``readPreference: secondary`` route reads to secondaries.
If ``$indexStats`` is collected only from the primary, indexes used exclusively
by secondary reads appear unused. Run with a connection URI pointing to each
replica set member or use ``readPreference=secondaryPreferred`` in the URI.

Background index builds
~~~~~~~~~~~~~~~~~~~~~~~

A newly built index may have ``ops == 0`` simply because it was still building
when the check ran. The warmup period (``--warmup-days``) mitigates this for
most cases.

Authors
=======

Carlos Salguero
