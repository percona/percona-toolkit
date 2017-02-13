pt-mongodb-summary
==================
**pt-mongodb-summary** collects information about a MongoDB cluster.

Usage
-----
pt-mongodb-summary [options] [host:[port]]

Default host:port is `localhost:27017`. 
For better results, host must be a **mongos** server.

Binaries
--------
Please check the `releases <https://github.com/percona/toolkit-go/releases>`_ tab to download the binaries.  

Paramters
^^^^^^^^^
===== ========= ======= ================================================================================
Short Long      Default Description
===== ========= ======= ================================================================================ 
u     user      empty   user name to use when connecting if DB auth is enabled
p     password  empty   password to use when connecting if DB auth is enabled
a     auth-db   admin   database used to establish credentials and privileges with a MongoDB server
===== ========= ======= ================================================================================

| 

``-p`` is an optional parameter. If it is used it shouldn't have a blank between the parameter and its value: `-p<password>`  
It can be also used as `-p` without specifying a password; in that case, the program will ask the password to avoid using a password in the command line.  


Output example
""""""""""""""
.. code-block:: html

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

Minimum auth role
^^^^^^^^^^^^^^^^^

This program needs to run some commands like ``getShardMap`` and to be able to run those commands
it needs to run under a user with the ``clusterAdmin`` or ``root`` built-in roles.

