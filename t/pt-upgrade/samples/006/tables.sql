DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (
  id    int(10) NOT NULL AUTO_INCREMENT,
  city  varchar(8) default NULL,
  PRIMARY KEY  (`id`)
);
INSERT INTO t VALUES
  (null,  'aaa'),
  (null,  'bbb'),
  (null,  'ccc');
