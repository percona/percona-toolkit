DROP DATABASE IF EXISTS onlythisdb;
CREATE DATABASE onlythisdb;
USE onlythisdb;
CREATE TABLE t (
  i INT,
  UNIQUE INDEX (i)
);
INSERT INTO onlythisdb.t VALUES (1), (2), (3);
