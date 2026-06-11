DROP DATABASE IF EXISTS pt_osc;
CREATE DATABASE pt_osc;
USE pt_osc;

CREATE TABLE t(
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    f1 INT
) ENGINE=InnoDB;

CREATE TABLE `person` (
 `id` bigint(20) NOT NULL AUTO_INCREMENT,
 `name` varchar(20) NOT NULL,
 `testId` bigint(20) DEFAULT NULL,
 PRIMARY KEY (`id`)
) ENGINE=InnoDB;

CREATE TABLE `test_table` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `refId` bigint(20) DEFAULT NULL,
  `person` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_person` (`person`),
  KEY `fk_refId` (`refId`),
  CONSTRAINT `fk_person` FOREIGN KEY (`person`) REFERENCES `person`(`id`),
  CONSTRAINT `fk_refId` FOREIGN KEY (`refId`) REFERENCES `test_table`(`id`)
) ENGINE=InnoDB;
