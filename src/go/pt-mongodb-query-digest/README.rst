.. _pt-mongodb-query-digest:

==================================
:program:`pt-mongodb-query-digest`
==================================

``pt-mongodb-query-digest`` reports query usage statistics
by aggregating queries from the MongoDB query profiler
or from the slow queries written to the MongoDB log files.

Usage
=====

.. code-block:: bash

   pt-mongodb-query-digest [OPTIONS] [host[:port]]
   pt-mongodb-query-digest [OPTIONS] logfile [logfile ...]

When a host is given (or nothing at all, which means ``localhost:27017``),
the tool connects to MongoDB and reads the ``system.profile`` collection
of the database specified with ``--database``.

When one or more log files are given, the tool doesn't connect to MongoDB
at all. It reads the slow queries from the files instead.
See `Reading from log files`_.

In both cases the results are grouped by fingerprint and namespace
(database.collection).
The fingerprint is calculated as a sorted list of keys in the document
with a maximum depth level of 10.
By default, the results are sorted by descending query count.

QPS is calculated using the time between the first and the last query
analyzed, like ``pt-query-digest`` does. This is the time covered by the
``system.profile`` collection (which is capped, so it only keeps the most
recent operations) or by the log files.

Reading from log files
======================

The profiler is not always an option. Maybe it is disabled because of
the overhead, maybe you don't have access to the server, or maybe you only
have the log files that were attached to a support ticket. In those cases
you can point the tool to the ``mongod`` (or ``mongos``) log files:

.. code-block:: bash

   pt-mongodb-query-digest /var/log/mongodb/mongod.log
   pt-mongodb-query-digest --database=shop --since=2h mongod.log.1 mongod.log
   zcat mongod.log.2.gz | pt-mongodb-query-digest -

MongoDB writes to the log every operation slower than ``slowms``
(100 milliseconds by default), even when the profiler is disabled
(profiling level 0). For example, to log every operation slower than
20 milliseconds without enabling the profiler:

.. code-block:: javascript

   db.setProfilingLevel(0, { slowms: 20 })

Use ``sampleRate`` to log only a fraction of the slow operations
on busy servers.

Things to keep in mind:

* Both the structured JSON log format (MongoDB 4.4 and newer) and the
  plain text format of MongoDB 4.2 and earlier are supported. The format
  is detected line by line.

* Multiple files are combined in a single report. Pass rotated files in
  chronological order: the client address and the authenticated user are
  taken from the connection and authentication messages, and a connection
  can start in one file and continue in the next one. Use ``-`` to read
  from the standard input.

* By default, queries on the ``admin``, ``local`` and ``config`` databases
  are skipped. Use ``--database`` to analyze only one database
  (including those).

* MongoDB logs each slow statement of an ``update`` or ``delete`` command
  in its own entry, and the whole command (the batch) in another one.
  The batch entry has no query shape, so it is ignored when its statements
  were logged, to avoid counting the same time twice. A batch can be slow
  even if none of its statements is, for example while waiting for the
  write concern. Those batches are reported as ``UPDATE <collection> (batch)``
  and ``DELETE <collection> (batch)``.

* Internal operations (like index builds, which are also logged as a
  ``createIndexes`` command) are ignored.

* Slow query entries that cannot be parsed are skipped. The number of
  skipped entries is reported as a warning. Use ``--log-level=debug`` to
  see where they are. For example, MongoDB 4.2 and earlier keep only the
  beginning and the end of lines longer than ``maxLogSizeKB``, so the
  command is lost. Since 4.4 the log keeps the first part of a truncated
  command; those entries are processed, but the query shape may miss the
  fields that were cut.

* Timestamps are shown in UTC.

Options
-------

``-?``, ``--help``
  Show help and exit

``-a``, ``--authenticationDatabase``
  Specifies the database used to establish credentials and privileges
  with a MongoDB server.
  By default, the ``admin`` database is used.

``-c``, ``--no-version-check``
  Don't check for updates

``-d``, ``--database``
  Specifies which database to profile.

  When reading log files, only queries on this database are analyzed.
  If not specified, queries on all databases except ``admin``, ``local``
  and ``config`` are analyzed.

``-f``, ``--output-format``
  Specifies the report output format. Valid options are: ``text``, ``json``.
  The default value is ``text``.

``-l``, ``--log-level``
  Specifies the log level:
  ``panic``, ``fatal``, ``error``, ``warn``, ``info``, ``debug error``

``-n``, ``--limit``
  Limits the number of queries to show

``-o``, ``--order-by``
  Specifies the sorting order using fields:
  ``count``, ``ratio``, ``query-time``, ``docs-examined`` (or ``docs-scanned``), ``docs-returned``.

  Adding a hyphen (``-``) in front of a field denotes reverse order.
  For example: ``--order-by="count,-ratio"``.

``-p``, ``--password``
  Specifies the password to use when connecting to a server
  with authentication enabled.

  Do not add a space between the option and its value: ``-p<password>``.

  If you specify the option without any value,
  you will be prompted for the password.

``--show-all``
  Comma separated list of attributes for which all the distinct values
  are shown. Valid attributes are: ``plan-summary``, ``app-name``,
  ``client``, ``user``.

  By default, only the values that fit in a single line are shown,
  followed by the number of values left out, like ``pt-query-digest`` does.
  The most frequent value is always shown, and values are never cut.

``--since``
  Only analyze queries newer than this value.

  The value can be a date and time, like ``2026-11-03T10:00:00Z``,
  ``"2026-11-03 10:00:00"`` or ``2026-11-03``, or a duration before the
  current time, like ``30m``, ``12h`` or ``7d`` (suffixes ``s``, ``m``,
  ``h`` and ``d`` are allowed).
  Dates without time zone are interpreted in the local time zone.

  Works for both the profiler and log files.

``--until``
  Only analyze queries older than this value.
  It uses the same format as ``--since``.

``-s``, ``--skip-collections``
  Comma separated list of collections to skip.
 
  Collection ``system.profile`` is skipped by default.

  It is possible to use an empty list by setting ``--skip-collections=""``.

``--sslCAFile``
  Specifies SSL CA cert file used for authentication.

``--sslPEMKeyFile``
  Specifies SSL client PEM file used for authentication.

``-u``, ``--user``
  Specifies the user name for connecting to a server
  with authentication enabled.

``-v``, ``--version``
  Show version and exit

Output Example
==============

.. code-block:: none

   # Query 2:  0.03 QPS, ID 97522d6adf564f7906bef33ae5563ac8
   # Ratio   94.12  (docs scanned/returned)
   # Time range: 2026-11-04 11:33:04.201 +0000 UTC to 2026-11-04 11:42:37.752 +0000 UTC
   # Attribute            pct     total        min         max        avg         95%        stddev      median
   # ==================   ===   ========    ========    ========    ========    ========     =======    ========
   # Count (docs)                    16
   # Exec Time ms          31      4712         103        1922         294         611         469         180
   # Docs Scanned          38     30.12K      20.00        3.00K       1.88K       3.00K       1.44K       3.00K
   # Docs Returned         35    320.00       20.00       20.00       20.00       20.00        0.00       20.00
   # Bytes sent            36     36.48K       2.25K       2.33K       2.28K       2.33K      38.73        2.25K
   # String:
   # Namespace           shop.orders
   # Operation           FIND
   # Fingerprint         FIND orders customerId,status
   # Plan Summary        COLLSCAN (10/62%)... 1 more
   # App Name            orders-api (8/50%), reporting (8/50%)
   # Client              10.0.4.17 (9/56%), 10.0.4.18 (7/43%)
   # User                appuser
   # Sample time         2026-11-04 11:40:12.311 +0000 UTC (slowest: 1922 ms)
   # Query               {"ns":"shop.orders","op":"query","command":{"find":"orders","filter":{"customerId":{"$numberInt":"2"},"status":"open"},"$db":"shop"}}

The ``# String:`` section shows, for each attribute, the distinct values seen
and how many times (and the percentage) each one was seen, most frequent first.
If there is only one value, it is shown alone. Values that don't fit in
a single line are summarized as ``... N more`` (see ``--show-all``).
Unlike ``pt-query-digest``, long values are never cut, since a partial
plan summary (like an incomplete index key pattern) is not useful.
Attributes without any value are not shown.

Like ``pt-query-digest``, the query shown is a sample: the slowest execution
of all the queries with the same fingerprint (if there is a tie, the last one).
``Sample time`` shows when it ran and how long it took, so you can find it
in the log file or in the ``system.profile`` collection.

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

:program:`pt-mongodb-query-digest` 3.7.2

