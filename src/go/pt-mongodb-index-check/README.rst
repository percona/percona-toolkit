.. _pt-mongodb-index-check:

=================================
:program:`pt-mongodb-index-check`
=================================

Performs checks on MongoDB indexes.

Checks available
================

Duplicated indexes
~~~~~~~~~~~~~~~~~~

Check for indexes that are the prefix of other indexes. For example if we have these 2 indexes

.. code-block:: javascript

   db.getSiblingDB("testdb").test_col.createIndex({"f1": 1, "f2": -1, "f3": 1, "f4": 1}, {"name": "idx_01"});
   db.getSiblingDB("testdb").test_col.createIndex({"f1": 1, "f2": -1, "f3": 1}, {"name": "idx_02"});


The index ``idx_02`` is the prefix of ``idx_01`` because it has the same
keys in the same order so, ``idx_02`` can be dropped.

Unused indexes.
~~~~~~~~~~~~~~~

This check gets the ``$indexstats`` for all indexes and reports those
having ``accesses.ops`` = 0.

Usage
=====

Run the program as ``pt-mongodb-index-check <command> [flags]``

Available commands
~~~~~~~~~~~~~~~~~~

================ ==================================
Command          Description
================ ==================================
check-duplicated Run checks for duplicated indexes.
check-unused     Run check for unused indexes.
check-all        Run all checks
================ ==================================

Available flags
~~~~~~~~~~~~~~~

+----------------------------+----------------------------------------+
| Flag                       | Description                            |
+============================+========================================+
| –all-databases             | Check in all databases excluding       |
|                            | system dbs.                            |
+----------------------------+----------------------------------------+
| –databases=DATABASES,…     | Comma separated list of databases to   |
|                            | check.                                 |
+----------------------------+----------------------------------------+
| –all-collections           | Check in all collections in the        |
|                            | selected databases.                    |
+----------------------------+----------------------------------------+
| –collections=COLLECTIONS,… | Comma separated list of collections to |
|                            | check.                                 |
+----------------------------+----------------------------------------+
| –mongodb.uri=              | Connection URI                         |
+----------------------------+----------------------------------------+
| –json                      | Show output as JSON                    |
+----------------------------+----------------------------------------+
| –version                   | Show version information               |
+----------------------------+----------------------------------------+

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

:program:`pt-mongodb-index-check` 3.7.1

