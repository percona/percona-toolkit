drop database if exists test;
create database test;
use test;

CREATE TABLE `t1` (
  `c1` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `c2` bigint(20) unsigned DEFAULT NULL,
  `c3` binary(20) DEFAULT NULL,
  PRIMARY KEY (`c1`),
  UNIQUE KEY `2bpk` (`c2`,`c3`),
  KEY `c3` (`c3`)
) ENGINE=InnoDB;

INSERT INTO t1 VALUES
  (null, 1, 1),
  (null, 1, 2),
  (null, 1, 3),
  (null, 1, 4),
  (null, 1, 5),
  (null, 2, 1),
  (null, 2, 2),
  (null, 2, 3),
  (null, 2, 4),
  (null, 2, 5);
