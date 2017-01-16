-- Setup database and test tables with self referencing FK

drop database if exists bug1632522;
create database bug1632522;
use bug1632522;

CREATE TABLE `person` (
 `id` bigint(20) NOT NULL AUTO_INCREMENT,
 `name` varchar(20) NOT NULL,
 `testId` bigint(20) DEFAULT NULL,
 PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `test_table` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `refId` bigint(20) DEFAULT NULL,
  `person` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_person` (`person`),
  KEY `fk_refId` (`refId`),
  CONSTRAINT `fk_person` FOREIGN KEY (`person`) REFERENCES `person` (`id`),
  CONSTRAINT `fk_refId` FOREIGN KEY (`refId`) REFERENCES `test_table` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

ALTER TABLE `person` ADD CONSTRAINT `fk_testId` FOREIGN KEY (`testId`) REFERENCES `test_table` (`id`);
