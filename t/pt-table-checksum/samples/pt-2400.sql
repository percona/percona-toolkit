DROP DATABASE IF EXISTS `pt-2400`;
CREATE DATABASE `pt-2400`;
USE `pt-2400`;
CREATE TABLE `apple` (
  `id` int NOT NULL,
  `name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`,`name`)
) ENGINE=InnoDB;

INSERT INTO `apple` VALUES
  (1, 'Granny Smith'),
  (2, 'Red Delicious'),
  (3, 'Golden Apple');
