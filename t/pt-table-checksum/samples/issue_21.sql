DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE issue_21 (
   a  INT,
   b  CHAR(1),
   UNIQUE INDEX (a)
) ENGINE=InnoDB;
INSERT INTO issue_21 VALUES (1,'a'),(2,'b'),(3,'c'),(4,'d'),(5,'e'),(6,'f');
