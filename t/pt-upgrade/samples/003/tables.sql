DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE t (
  id         int(10) NOT NULL AUTO_INCREMENT,
  username   varchar(8) default NULL,
  PRIMARY KEY  (`id`)
);
INSERT INTO t VALUES (1, 'username');
