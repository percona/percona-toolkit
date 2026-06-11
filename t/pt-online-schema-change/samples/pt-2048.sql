DROP DATABASE IF EXISTS test;
CREATE DATABASE test;

USE test;

DROP TABLE IF EXISTS `joinit`;

CREATE TABLE `joinit` (
  `i` int(11) NOT NULL AUTO_INCREMENT,
  `s` varchar(64) DEFAULT NULL,
  `t` time NOT NULL,
  `g` int(11) NOT NULL,
  PRIMARY KEY (`i`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

INSERT INTO joinit VALUES (NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )));
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
INSERT INTO joinit SELECT NULL, uuid(), time(now()),  (FLOOR( 1 + RAND( ) *60 )) FROM joinit;
