DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE t (
   i int unsigned not null,
   v varchar(16),
   t tinyint
);
INSERT INTO t VALUES (1,'hi',1);
