-- Schema for testing pt-archiver --bulk-insert with special characters
-- (tabs, newlines, backslashes) to ensure no field misalignment.
DROP DATABASE IF EXISTS `bulk_escape`;
CREATE DATABASE `bulk_escape`;

CREATE TABLE `bulk_escape`.`source` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(500) DEFAULT NULL,
  `job` varchar(450) DEFAULT NULL,
  `stu_id` int DEFAULT NULL,
  `title` varchar(450) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `bulk_escape`.`dest` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(500) DEFAULT NULL,
  `job` varchar(450) DEFAULT NULL,
  `stu_id` int DEFAULT NULL,
  `title` varchar(450) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
