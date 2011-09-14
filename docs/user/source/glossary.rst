==========
 Glossary
==========

.. glossary::

   lsn
     --

   LSN
     --

   InnoDB
      Storage engine which provides ACID-compilant transactions and foreing key support, among others improvements over :term:`MyISAM`. It is the default engine for |MySQL| as of the 5.5 series.

   MyISAM
     Previous default storage engine for |MySQL| for versions prior to 5.5. It doesn't fully support transactions but in some scenarios may be faster than :term:`InnoDB`.

   XtraDB
     *Percona XtraDB* is an enhanced version of the InnoDB storage engine, designed to better scale on modern hardware, and including a variety of other features useful in high performance environments. It is fully backwards compatible, and so can be used as a drop-in replacement for standard InnoDB. More information `here <http://www.percona.com/docs/wiki/Percona-XtraDB:start>`_ .

   my.cnf
     This file refers to the database server's main configuration file. Most linux distributions place it as :file:`/etc/mysql/my.cnf`, but the location and name depends on the particular installation. Note that this is not the only way of configuring the server, some systems does not have one even and rely on the command options to start the server and its defaults values.

   datadir
    The directory in which the database server stores its databases. Most Linux distribution use :file:`/var/lib/mysql` by default.

   ibdata
     Default prefix for tablespace files, e.g. :file:`ibdata1` is a 10MB  autoextensible file that |MySQL| creates for the shared tablespace by default. 


