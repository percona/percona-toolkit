-- Test case for timestamp NULL issue during column rename
-- This reproduces the issue where 't' column values become NULL after CHANGE COLUMN

DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `joinit` (
 `i` int(11) NOT NULL AUTO_INCREMENT,
 `s` varchar(64) DEFAULT NULL,
 `t1` time DEFAULT NULL,
 `g` int(11) NOT NULL,
 PRIMARY KEY (`i`)
);

-- Insert initial data with timestamps
INSERT INTO joinit VALUES (NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )));
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit; 