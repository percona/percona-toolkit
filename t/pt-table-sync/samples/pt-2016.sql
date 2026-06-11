DROP DATABASE IF EXISTS test;

CREATE DATABASE test;

CREATE TABLE test.test2 (
  col1 INT NOT NULL,
  col2 TEXT NOT NULL,
  col3 VARCHAR(5) NOT NULL,
  UNIQUE KEY (col1, col2(3))
);

INSERT INTO test.test2 VALUES(1,'aaa','aaa');
