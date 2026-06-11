CREATE DATABASE IF NOT EXISTS `percona`;

CREATE TABLE `percona`.`checksums` (
   db             CHAR(64)     NOT NULL,
   tbl            CHAR(64)     NOT NULL,
   chunk          INT          NOT NULL,
   chunk_time     FLOAT            NULL,
   chunk_index    VARCHAR(200)     NULL,
   lower_boundary TEXT             NULL,
   upper_boundary TEXT             NULL,
   this_crc       CHAR(40)     NOT NULL,
   this_cnt       INT          NOT NULL,
   source_crc     CHAR(40)         NULL,
   source_cnt     INT              NULL,
   ts             TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
   PRIMARY KEY (db, tbl, chunk),
   INDEX ts_db_tbl (ts, db, tbl)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE DATABASE IF NOT EXISTS test;

CREATE TABLE `test`.`dsns` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `parent_id` int(11) DEFAULT NULL,
  `dsn` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
);

-- From Sandbox.pm
-- chan_master1 => 2900,
-- chan_master2 => 2901,
-- chan_slave1  => 2902,
-- chan_slave2  => 2903,

INSERT INTO `test`.`dsns` VALUES
(1, NULL, "h=127.0.0.1,P=2902,u=msandbox,p=msandbox"),
(2, NULL, "h=127.0.0.1,P=2903,u=msandbox,p=msandbox");
