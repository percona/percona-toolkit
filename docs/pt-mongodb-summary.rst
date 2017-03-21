.. pt-mongodb-summary:

==================
pt-mongodb-summary
==================

``pt-mongodb-summary`` collects information about a MongoDB cluster.
It collects information from several sources
to provide an overview of the cluster.

Usage
=====

.. code-block:: bash

   pt-mongodb-summary [OPTIONS] [HOST[:PORT]]

By default, if you run ``pt-mongodb-summary`` without any parameters,
it will try to connect to ``localhost`` on port ``27017``.
The program collects information about MongoDB instances
by running administration commands and formatting the output.

.. note:: ``pt-mongodb-summary`` requires to be run by user
   with the ``clusterAdmin`` or ``root`` built-in roles.

.. note:: ``pt-mongodb-summary`` cannot collect statistics
   from MongoDB instances that require connection via SSL.
   Support for SSL will be added in the future.

Options
-------

``-a``, ``--auth-db``
  Specifies the database used to establish credentials and privileges
  with a MongoDB server.
  By default, the ``admin`` database is used.

``-p``, ``--password``
  Specifies the password to use when connecting to a server
  with authentication enabled.

  Do not add a space between the option and its value: ``-p<password>``.

  If you specify the option without any value,
  ``pt-mongodb-summary`` will ask for password interactively.

``-u``, ``--user``
  Specifies the user name for connecting to a server
  with authentication enabled.

Output Example
==============

.. code-block:: none

   # Instances ####################################################################################
   ID    Host                         Type                                 ReplSet  
     0 localhost:17001                PRIMARY                                r1 
     1 localhost:17002                SECONDARY                              r1 
     2 localhost:17003                SECONDARY                              r1 
     0 localhost:18001                PRIMARY                                r2 
     1 localhost:18002                SECONDARY                              r2 
     2 localhost:18003                SECONDARY                              r2
   
   # This host
   # Mongo Executable #############################################################################
          Path to executable | /home/karl/tmp/MongoDB32Labs/3.0/bin/mongos
   # Report On 0 ########################################
                        User | karl
                   PID Owner | mongos
                        Time | 2016-10-30 00:18:49 -0300 ART
                    Hostname | karl-HP-ENVY
                     Version | 3.0.11
                    Built On | Linux x86_64
                     Started | 2016-10-30 00:18:49 -0300 ART
                     Datadir | /data/db
                Process Type | mongos
   
   # Running Ops ##################################################################################
   
   Type         Min        Max        Avg
   Insert           0          0          0/5s
   Query            0          0          0/5s
   Update           0          0          0/5s
   Delete           0          0          0/5s
   GetMore          0          0          0/5s
   Command          0         22         16/5s
   
   # Security #####################################################################################
   Users 0
   Roles 0
   Auth  disabled
   SSL   disabled
   
   
   # Oplog ########################################################################################
   Oplog Size     18660 Mb
   Oplog Used     55 Mb
   Oplog Length   0.91 hours
   Last Election  2016-10-30 00:18:44 -0300 ART
   
   
   # Cluster wide #################################################################################
               Databases: 3
             Collections: 17
     Sharded Collections: 1
   Unsharded Collections: 16
       Sharded Data Size: 68 GB
     Unsharded Data Size: 0 KB
   # Balancer (per day)
                 Success: 6
                  Failed: 0
                  Splits: 0
                   Drops: 0

Sections
--------

Output is separated into the following sections:

* **Instances**

  This section lists all hosts connected to the current MongoDB instance.
  For this, ``pt-mongodb-summary`` runs the ``listShards`` command
  and then the ``replSetGetStatus`` on every instance
  to collect its ID, type, and replica set.

* **This host**

  This section provides an overview of the current MongoDB instance
  and the underlying OS.
  For this, ``pt-mongodb-summary`` groups information
  collected from ``hostInfo``, ``getCmdLineOpts``, ``serverStatus``,
  and the OS process (by process ID).

* **Running Ops**

  This section provides minimum, maximum, and average operation counters
  for ``insert``, ``query``, ``update``, ``delete``, ``getMore``,
  and ``command`` operations.
  For this, ``pt-mongodb-summary`` runs the ``serverStatus`` command
  5 times at regular intervals (every second).

* **Security**

  This section provides information about the security settings.
  For this, ``pt-mongodb-summary``, parses ``getCmdLineOpts`` output
  and queries the ``admin.system.users``
  and ``admin.system.roles`` collections.

* **Oplog**

  This section contains details about the MongoDB operations log (oplog).
  For this, ``pt-mongodb-summary`` collects statistics
  from the oplog on every host in the cluster,
  and returns those with the smallest ``TimeDiffHours`` value.

* **Cluster wide**

  This section provides information about the number of sharded and
  unsharded databases, collections, and their size.
  For this, ``pt-mongodb-summary`` runs the ``listDatabases`` command
  and then runs ``collStats`` for every collection in every database.

