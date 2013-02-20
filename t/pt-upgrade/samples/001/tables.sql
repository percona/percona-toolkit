DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (
  id         int(10) NOT NULL AUTO_INCREMENT,
  username   varchar(8) default NULL,
  last_login datetime default NULL,
  PRIMARY KEY  (`id`)
);
INSERT INTO t VALUES
  (null,  'a',  '2013-01-01 00:00:01'),
  (null,  'b',  '2013-01-01 00:00:02'),
  (null,  'c',  '2013-01-01 00:00:03'),
  (null,  'd',  '2013-01-01 00:00:04'),
  (null,  'e',  '2013-01-01 00:00:05'),
  (null,  'f',  '2013-01-01 00:00:06');
