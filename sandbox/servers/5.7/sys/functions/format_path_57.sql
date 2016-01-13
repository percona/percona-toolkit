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

DROP FUNCTION IF EXISTS format_path;

DELIMITER $$

CREATE DEFINER='root'@'localhost' FUNCTION format_path (
        path VARCHAR(512)
    )
    RETURNS VARCHAR(512) CHARSET UTF8
    COMMENT '
             Description
             -----------

             Takes a raw path value, and strips out the datadir or tmpdir
             replacing with @@datadir and @@tmpdir respectively. 

             Also normalizes the paths across operating systems, so backslashes
             on Windows are converted to forward slashes

             Parameters
             -----------

             path (VARCHAR(512)):
               The raw file path value to format.

             Returns
             -----------

             VARCHAR(512) CHARSET UTF8

             Example
             -----------

             mysql> select @@datadir;
             +-----------------------------------------------+
             | @@datadir                                     |
             +-----------------------------------------------+
             | /Users/mark/sandboxes/SmallTree/AMaster/data/ |
             +-----------------------------------------------+
             1 row in set (0.06 sec)

             mysql> select format_path(\'/Users/mark/sandboxes/SmallTree/AMaster/data/mysql/proc.MYD\') AS path;
             +--------------------------+
             | path                     |
             +--------------------------+
             | @@datadir/mysql/proc.MYD |
             +--------------------------+
             1 row in set (0.03 sec)
            '
    SQL SECURITY INVOKER
    DETERMINISTIC
    NO SQL
BEGIN
  DECLARE v_path VARCHAR(512);
  DECLARE v_undo_dir VARCHAR(1024);

  -- OSX hides /private/ in variables, but Performance Schema does not
  IF path LIKE '/private/%' 
    THEN SET v_path = REPLACE(path, '/private', '');
    ELSE SET v_path = path;
  END IF;

  -- @@global.innodb_undo_directory is only set when separate undo logs are used
  SET v_undo_dir = IFNULL((SELECT VARIABLE_NAME FROM performance_schema.global_variables WHERE VARIABLE_NAME = 'innodb_undo_directory'), '');

  IF v_path IS NULL THEN RETURN NULL;
  ELSEIF v_path LIKE CONCAT(@@global.datadir, '%') ESCAPE '|' THEN
    RETURN REPLACE(REPLACE(REPLACE(v_path, @@global.datadir, '@@datadir/'), '\\\\', ''), '\\', '/');
  ELSEIF v_path LIKE CONCAT(@@global.tmpdir, '%') ESCAPE '|' THEN
    RETURN REPLACE(REPLACE(REPLACE(v_path, @@global.tmpdir, '@@tmpdir/'), '\\\\', ''), '\\', '/');
  ELSEIF v_path LIKE CONCAT(@@global.slave_load_tmpdir, '%') ESCAPE '|' THEN
    RETURN REPLACE(REPLACE(REPLACE(v_path, @@global.slave_load_tmpdir, '@@slave_load_tmpdir/'), '\\\\', ''), '\\', '/');
  ELSEIF v_path LIKE CONCAT(@@global.innodb_data_home_dir, '%') ESCAPE '|' THEN
    RETURN REPLACE(REPLACE(REPLACE(v_path, @@global.innodb_data_home_dir, '@@innodb_data_home_dir/'), '\\\\', ''), '\\', '/');
  ELSEIF v_path LIKE CONCAT(@@global.innodb_log_group_home_dir, '%') ESCAPE '|' THEN
    RETURN REPLACE(REPLACE(REPLACE(v_path, @@global.innodb_log_group_home_dir, '@@innodb_log_group_home_dir/'), '\\\\', ''), '\\', '/');
  ELSEIF v_path LIKE CONCAT(v_undo_dir, '%') ESCAPE '|' THEN
    RETURN REPLACE(REPLACE(REPLACE(v_path, v_undo_dir, '@@innodb_undo_directory/'), '\\\\', ''), '\\', '/');
  ELSE RETURN v_path;
  END IF;
END$$

DELIMITER ;
