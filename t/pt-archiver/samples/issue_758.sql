DROP DATABASE IF EXISTS issue_758;
CREATE DATABASE issue_758;
USE issue_758;
CREATE TABLE t (
  i int,
  unique key (i)
);
INSERT INTO issue_758.t VALUES (1),(2);
