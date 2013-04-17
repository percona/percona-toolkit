drop database if exists test1002448;
create database test1002448;
use test1002448;

CREATE TABLE `table_name` (
  `site` varchar(20) NOT NULL DEFAULT '',
  `update_name` varchar(32) NOT NULL DEFAULT '',
  `user` varchar(64) NOT NULL DEFAULT '',
  `time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `value` varchar(64) NOT NULL DEFAULT '',
  UNIQUE KEY `site` (`site`,`update_name`,`user`,`value`),
  KEY `user` (`user`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1

