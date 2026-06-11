DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE test.t1 (
id int AUTO_INCREMENT PRIMARY KEY,
f2 int, 
f3 int NULL,
f4 int
);

INSERT INTO test.t1 VALUES
(1,1,1,1), 
(2,1,1,1), 
(3,1,2,1), 
(4,2,NULL,2), 
(5,3,NULL,2),
(6,4,4,4), 
(7,4,4,4);
