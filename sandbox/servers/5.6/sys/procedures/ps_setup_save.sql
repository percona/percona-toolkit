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

DROP PROCEDURE IF EXISTS ps_setup_save;

DELIMITER $$

CREATE DEFINER='root'@'localhost' PROCEDURE ps_setup_save (
        IN in_timeout INT
    )
    COMMENT '
             Description
             -----------

             Saves the current configuration of Performance Schema,
             so that you can alter the setup for debugging purposes,
             but restore it to a previous state.

             Use the companion procedure - ps_setup_reload_saved(), to
             restore the saved config.

             Requires the SUPER privilege for "SET sql_log_bin = 0;".

             Parameters
             -----------

             None.

             Example
             -----------

             mysql> CALL sys.ps_setup_save();
             Query OK, 0 rows affected (0.08 sec)

             mysql> UPDATE performance_schema.setup_instruments
                 ->    SET enabled = \'YES\', timed = \'YES\';
             Query OK, 547 rows affected (0.40 sec)
             Rows matched: 784  Changed: 547  Warnings: 0

             /* Run some tests that need more detailed instrumentation here */

             mysql> CALL sys.ps_setup_reload_saved();
             Query OK, 0 rows affected (0.32 sec)
            '
    SQL SECURITY INVOKER
    NOT DETERMINISTIC
    MODIFIES SQL DATA
BEGIN
    DECLARE v_lock_result INT;

    SET @log_bin := @@sql_log_bin;
    SET sql_log_bin = 0;

    SELECT GET_LOCK('sys.ps_setup_save', in_timeout) INTO v_lock_result;

    IF v_lock_result THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_setup_actors;
        DROP TEMPORARY TABLE IF EXISTS tmp_setup_consumers;
        DROP TEMPORARY TABLE IF EXISTS tmp_setup_instruments;
        DROP TEMPORARY TABLE IF EXISTS tmp_threads;

        CREATE TEMPORARY TABLE tmp_setup_actors LIKE performance_schema.setup_actors;
        CREATE TEMPORARY TABLE tmp_setup_consumers LIKE performance_schema.setup_consumers;
        CREATE TEMPORARY TABLE tmp_setup_instruments LIKE performance_schema.setup_instruments;
        CREATE TEMPORARY TABLE tmp_threads (THREAD_ID bigint unsigned NOT NULL PRIMARY KEY, INSTRUMENTED enum('YES','NO') NOT NULL);

        INSERT INTO tmp_setup_actors SELECT * FROM performance_schema.setup_actors;
        INSERT INTO tmp_setup_consumers SELECT * FROM performance_schema.setup_consumers;
        INSERT INTO tmp_setup_instruments SELECT * FROM performance_schema.setup_instruments;
        INSERT INTO tmp_threads SELECT THREAD_ID, INSTRUMENTED FROM performance_schema.threads;
    ELSE
        SIGNAL SQLSTATE VALUE '90000'
           SET MESSAGE_TEXT = 'Could not lock the sys.ps_setup_save user lock, another thread has a saved configuration';
    END IF;

    SET sql_log_bin = @log_bin;
END$$

DELIMITER ;
