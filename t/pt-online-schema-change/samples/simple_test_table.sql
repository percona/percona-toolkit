DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE `test` (
  `id` int(11) NOT NULL,
  `name` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

