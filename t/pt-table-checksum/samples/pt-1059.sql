CREATE SCHEMA IF NOT EXISTS pt_1059;
USE pt_1059;
DROP TABLE IF EXISTS t1;
CREATE TABLE `t1` (
`id` int(10) unsigned NOT NULL AUTO_INCREMENT,
`c` char(1) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `idx_with_
newline` (`c`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO t1 (c) VALUES('a'),('b'),('c');

DROP TABLE IF EXISTS t2;
CREATE TABLE `t2` (
`id` int(10) unsigned NOT NULL AUTO_INCREMENT,
`column_with_
newline` char(1) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `idx_c` (`column_with_
newline`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO t2 (`column_with_
newline`) VALUES('a'),('b'),('c');

DROP TABLE IF EXISTS t3;
CREATE TABLE `t3` (
`id` int(10) unsigned NOT NULL AUTO_INCREMENT,
`column_with_
newline` char(1) DEFAULT NULL,
PRIMARY KEY (`id`),
KEY `idx_with_
newline` (`column_with_
newline`) 
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO t3 (`column_with_
newline`) VALUES('a'),('b'),('c');
