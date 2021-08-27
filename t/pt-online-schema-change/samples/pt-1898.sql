-- give master some advantage on performance
SET GLOBAL innodb_flush_log_at_trx_commit=2;
SET GLOBAL sync_binlog=1000000;
SET GLOBAL innodb_buffer_pool_size=2*1024*1024*1024;

DROP DATABASE IF EXISTS test;
CREATE DATABASE test;.
USE test;
 
DROP TABLE IF EXISTS `joinit`;
 
CREATE TABLE `joinit` (
 `i` int(11) NOT NULL AUTO_INCREMENT,
 `s` varchar(64) DEFAULT NULL,
 `t` time NOT NULL,
 `g` int(11) NOT NULL,
 PRIMARY KEY (`i`),
 KEY g_idx (g)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO joinit VALUES (NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )));
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit; -- +256 rows
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit; -- +512 rows
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit; -- +1024 rows
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit; 
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit; 
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit; 
INSERT INTO joinit SELECT NULL, uuid(), time(now()), (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
