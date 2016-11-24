CREATE DATABASE IF NOT EXISTS test;
DROP TABLE IF EXISTS test.ConfigData;
CREATE TABLE `test`.`ConfigData` (
  `primaryKey` bigint(20) NOT NULL AUTO_INCREMENT,
  `id` varchar(36) DEFAULT NULL,
  `parentEntity_primaryKey` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`primaryKey`),
  KEY `parentEntityPrimaryKey` (`parentEntity_primaryKey`)
)ENGINE=InnoDB DEFAULT CHARSET=latin1;
