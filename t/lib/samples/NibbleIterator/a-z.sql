DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE t (
  c varchar(16) not null,
  index (c)
);

INSERT INTO t VALUES ('a'), ('b'), ('c'), ('d'), ('e'), ('f'), ('g'), ('h'), ('i'), ('j'), ('k'), ('l'), ('m'), ('n'), ('o'), ('p'), ('q'), ('r'), ('s'), ('t'), ('u'), ('v'), ('w'), ('x'), ('y'), ('z');
