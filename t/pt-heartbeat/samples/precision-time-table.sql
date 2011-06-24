DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE heartbeat (
  ts                    varchar(26) NOT NULL,
  server_id             int unsigned NOT NULL PRIMARY KEY,
  file                  varchar(255) DEFAULT NULL,    -- SHOW MASTER STATUS
  position              bigint unsigned DEFAULT NULL, -- SHOW MASTER STATUS
  relay_master_log_file varchar(255) DEFAULT NULL,    -- SHOW SLAVE STATUS 
  exec_master_log_pos   bigint unsigned DEFAULT NULL  -- SHOW SLAVE STATUS
) ENGINE=MEMORY;
