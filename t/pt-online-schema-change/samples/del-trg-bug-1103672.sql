drop database if exists test;
create database test;
use test;

CREATE TABLE `t1` (
  `id` int(10) unsigned NOT NULL,
  `x` char(3) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

INSERT INTO t1 VALUES
  (1, 'a'),
  (2, 'b'),
  (3, 'c'),
  (4, 'd'),
  (5, 'f'),
  (6, 'g'),
  (7, 'h'),
  (8, 'i'),
  (9, 'j');
