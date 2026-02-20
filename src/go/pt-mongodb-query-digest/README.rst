.. _pt-mongodb-query-digest:

==================================
:program:`pt-mongodb-query-digest`
==================================

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
  ``count``, ``ratio``, ``query-time``, ``docs-examined``, ``docs-returned``.

  Adding a hyphen (``-``) in front of a field denotes reverse order.
  For example: ``--order-by="count,-ratio"``.

``-p``, ``--password``
  Specifies the password to use when connecting to a server
  with authentication enabled.

  Do not add a space between the option and its value: ``-p<password>``.

  If you specify the option without any value,
  you will be prompted for the password.

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

   # Query 3:  0.06 QPS, ID 0b906bd86148def663d11b402f3e41fa
   # Ratio    1.00  (docs examined/returned)
   # Time range: 2017-02-03 16:01:37.484 -0300 ART to 2017-02-03 16:02:08.43 -0300 ART
   # Attribute            pct     total        min         max        avg         95%        stddev      median
   # ==================   ===   ========    ========    ========    ========    ========     =======    ========
   # Count (docs)                   100
   # Exec Time ms           2         3           0           1           0           0           0           0
   # Docs Examined          5      7.50K      75.00       75.00       75.00       75.00        0.00       75.00
   # Docs Returned         92      7.50K      75.00       75.00       75.00       75.00        0.00       75.00
   # Bytes recv             1    106.12M       1.06M       1.06M       1.06M       1.06M       0.00        1.06M
   # String:
   # Namespaces          samples.col1
   # Operation           query
   # Fingerprint         find,shardVersion
   # Query               {"find":"col1","shardVersion":[0,"000000000000000000000000"]}

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

:program:`pt-mongodb-query-digest` 3.7.1

