.. _pt-mongodb-query-digest:

=======================
pt-mongodb-query-digest
=======================

``pt-mongodb-query-digest`` reports query usage statistics
by aggregating queries from MongoDB query profiler.

Usage
=====

.. code-block:: bash

   pt-mongodb-query-digest [OPTIONS]

It runs the following command::

 db.getSiblingDB("samples").system.profile.find({"op":{"$nin":["getmore", "delete"]}});

Then the results are grouped by fingerprint and namespace
(database.collection).
The fingerprint is calculated as a sorted list of keys in the document
with a maximum depth level of 10.
By default, the results are sorted by ascending query count.

.. note:: ``pt-mongodb-query-digest`` cannot collect statistics
   from MongoDB instances that require connection via SSL.
   Support for SSL will be added in the future.

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
  Specifies which database to profile

``-l``, ``--log-level``
  Specifies the log level:
  ``panic``, ``fatal``, ``error``, ``warn``, ``info``, ``debug error``

``-n``, ``--limit``
  Limits the number of queries to show

``-o``, ``--order-by``
  Specifies the sorting order using fields:
  ``count``, ``ratio``, ``query-time``, ``docs-scanned``, ``docs-returned``.

  Adding a hypen (``-``) in front of a field denotes reverse order.
  For example: ``--order-by="count,-ratio"``.

``-p``, ``--password``
  Specifies the password to use when connecting to a server
  with authentication enabled.

  Do not add a space between the option and its value: ``-p<password>``.

  If you specify the option without any value,
  you will be prompted for the password.

``-u``, ``--user``
  Specifies the user name for connecting to a server
  with authentication enabled.

``-v``, ``--version``
  Show version and exit

Output Example
==============

.. code-block:: none

   # Query 2:  0.00 QPS, ID 1a6443c2db9661f3aad8edb6b877e45d
   # Ratio    1.00  (docs scanned/returned)
   # Time range: 2017-01-11 12:58:26.519 -0300 ART to 2017-01-11 12:58:26.686 -0300 ART
   # Attribute            pct     total        min         max        avg         95%        stddev      median
   # ==================   ===   ========    ========    ========    ========    ========     =======    ========
   # Count (docs)                    36 
   # Exec Time ms           0         0           0           0           0           0           0           0 
   # Docs Scanned           0    148.00        0.00       74.00        4.11       74.00       16.95        0.00 
   # Docs Returned          2    148.00        0.00       74.00        4.11       74.00       16.95        0.00 
   # Bytes recv             0      2.11M     215.00        1.05M      58.48K       1.05M     240.22K     215.00 
   # String:
   # Namespaces          samples.col1
   # Fingerprint         $gte,$lt,$meta,$sortKey,filter,find,projection,shardVersion,sort,user_id,user_id


