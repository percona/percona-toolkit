DROP DATABASE IF EXISTS test;
CREATE DATABASE test;

CREATE TABLE `test`.`t1` (
  f1 INT NOT NULL,
  f2 VARCHAR(10)
) Engine=InnoDB;

INSERT INTO `test`.`t1` VALUES
(1, 'a'),
(2, 'b'),
(3, 'c'),
(4, 'd'),
(5, 'e'),
(6, 'f'),
(7, 'g'),
(8, 'h'),
(9, 'i'),
(10, 'j');

