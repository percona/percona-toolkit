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

