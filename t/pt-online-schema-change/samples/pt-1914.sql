DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `aaa` (
 `id` int(11) NOT NULL AUTO_INCREMENT,
 `Password` varchar(100) NOT NULL DEFAULT '' COMMENT 'Generated',
 `v` int(11) DEFAULT NULL,
 PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;

INSERT INTO test.aaa VALUES 
(1, "a", 1), 
(2, "b", 2), 
(3, "c", NULL),
(4, "d", 4),
(5, "e", NULL), 
(6, "f", 6);
