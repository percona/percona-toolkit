DROP DATABASE IF EXISTS issue_611;
CREATE DATABASE issue_611;
USE issue_611;
CREATE TABLE t (
  id int primary key,
  foo char
) PARTITION BY KEY (id);
INSERT INTO t VALUES (1,'a'),(2,'b'),(3,'c'),(4,'d'),(5,'e');
