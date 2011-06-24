DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
use test;
CREATE TABLE a (
  id int primary key, -- doesn't map
  c  varchar(16)
);

INSERT INTO a VALUES
  (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd'), (5, 'e');

CREATE TABLE b (
  b_id int auto_increment primary key,
  c  varchar(16)
);

CREATE TABLE c (
  c_id int auto_increment primary key,
  c  varchar(16)
);
