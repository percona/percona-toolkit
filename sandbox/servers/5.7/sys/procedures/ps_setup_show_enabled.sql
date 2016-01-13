-- Copyright (c) 2014, 2015, Oracle and/or its affiliates. All rights reserved.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; version 2 of the License.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

DROP PROCEDURE IF EXISTS ps_setup_show_enabled;

DELIMITER $$

CREATE DEFINER='root'@'localhost' PROCEDURE ps_setup_show_enabled (
        IN in_show_instruments BOOLEAN,
        IN in_show_threads BOOLEAN
    )
    COMMENT '
             Description
             -----------

             Shows all currently enabled Performance Schema configuration.

             Parameters
             -----------

             in_show_instruments (BOOLEAN):
               Whether to print enabled instruments (can print many items)

             in_show_threads (BOOLEAN):
               Whether to print enabled threads

             Example
             -----------

             mysql> CALL sys.ps_setup_show_enabled(TRUE, TRUE);
             +----------------------------+
             | performance_schema_enabled |
             +----------------------------+
             |                          1 |
             +----------------------------+
             1 row in set (0.00 sec)

             +---------------+
             | enabled_users |
             +---------------+
             | \'%\'@\'%\'       |
             +---------------+
             1 row in set (0.01 sec)

             +----------------------+---------+-------+
             | objects              | enabled | timed |
             +----------------------+---------+-------+
             | mysql.%              | NO      | NO    |
             | performance_schema.% | NO      | NO    |
             | information_schema.% | NO      | NO    |
             | %.%                  | YES     | YES   |
             +----------------------+---------+-------+
             4 rows in set (0.01 sec)

             +---------------------------+
             | enabled_consumers         |
             +---------------------------+
             | events_statements_current |
             | global_instrumentation    |
             | thread_instrumentation    |
             | statements_digest         |
             +---------------------------+
             4 rows in set (0.05 sec)

             +--------------------------+-------------+
             | enabled_threads          | thread_type |
             +--------------------------+-------------+
             | innodb/srv_master_thread | BACKGROUND  |
             | root@localhost           | FOREGROUND  |
             | root@localhost           | FOREGROUND  |
             | root@localhost           | FOREGROUND  |
             | root@localhost           | FOREGROUND  |
             +--------------------------+-------------+
             5 rows in set (0.03 sec)

             +-------------------------------------+-------+
             | enabled_instruments                 | timed |
             +-------------------------------------+-------+
             | wait/io/file/sql/map                | YES   |
             | wait/io/file/sql/binlog             | YES   |
             ...
             | statement/com/Error                 | YES   |
             | statement/com/                      | YES   |
             | idle                                | YES   |
             +-------------------------------------+-------+
             210 rows in set (0.08 sec)

             Query OK, 0 rows affected (0.89 sec)
            '
    SQL SECURITY INVOKER
    DETERMINISTIC
    READS SQL DATA
BEGIN
    SELECT @@performance_schema AS performance_schema_enabled;

    SELECT CONCAT('\'', host, '\'@\'', user, '\'') AS enabled_users
      FROM performance_schema.setup_actors;

    SELECT object_type,
           CONCAT(object_schema, '.', object_name) AS objects,
           enabled,
           timed
      FROM performance_schema.setup_objects;

    SELECT name AS enabled_consumers
      FROM performance_schema.setup_consumers
     WHERE enabled = 'YES';

    IF (in_show_threads) THEN
        SELECT IF(name = 'thread/sql/one_connection', 
                  CONCAT(processlist_user, '@', processlist_host), 
                  REPLACE(name, 'thread/', '')) AS enabled_threads,
        TYPE AS thread_type
          FROM performance_schema.threads
         WHERE INSTRUMENTED = 'YES';
    END IF;

    IF (in_show_instruments) THEN
        SELECT name AS enabled_instruments,
               timed
          FROM performance_schema.setup_instruments
         WHERE enabled = 'YES';
    END IF;
END$$

DELIMITER ;
