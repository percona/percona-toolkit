--
-- Host: localhost    Database: test
-- ------------------------------------------------------
-- Server version	5.1.53-log

SET FOREIGN_KEY_CHECKS=0;

DROP TABLE IF EXISTS `address`;
CREATE TABLE `address` (
  `address_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `address` varchar(50) NOT NULL,
  `city_id` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`address_id`),
  KEY `idx_fk_city_id` (`city_id`),
  CONSTRAINT `fk_address_city` FOREIGN KEY (`city_id`) REFERENCES `city` (`city_id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DROP TABLE IF EXISTS `city`;
CREATE TABLE `city` (
  `city_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `city` varchar(50) NOT NULL,
  `country_id` smallint(5) unsigned NOT NULL,
  PRIMARY KEY (`city_id`),
  KEY `idx_fk_country_id` (`country_id`),
  CONSTRAINT `fk_city_country` FOREIGN KEY (`country_id`) REFERENCES `country` (`country_id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DROP TABLE IF EXISTS `country`;
CREATE TABLE `country` (
  `country_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `country` varchar(50) NOT NULL,
  PRIMARY KEY (`country_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DROP TABLE IF EXISTS `denorm_address`;
CREATE TABLE `denorm_address` (
  `address_id` smallint(5) unsigned NOT NULL,
  `address` varchar(50) NOT NULL,
  `city_id` smallint(5) unsigned NOT NULL,
  `city` varchar(50) NOT NULL,
  `country_id` smallint(5) unsigned NOT NULL,
  `country` varchar(50) NOT NULL,
  PRIMARY KEY (`address_id`,`city_id`,`country_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

LOCK TABLES `denorm_address` WRITE;
INSERT INTO `denorm_address` VALUES
  (1,'47 MySakila Drive',300,'Lethbridge',20,'Canada'),
  (2,'28 MySQL Boulevard',576,'Woodridge',8,'Australia'),
  (3,'23 Workhaven Lane',300,'Lethbridge',20,'Canada'),
  (4,'1411 Lillydale Drive',576,'Woodridge',8,'Australia'),
  (5,'1913 Hanoi Way',463,'Sasebo',50,'Japan'),
  (6,'1121 Loja Avenue',449,'San Bernardino',103,'United States'),
  (7,'692 Joliet Street',38,'Athenai',39,'Greece'),
  (8,'1566 Inegl Manor',349,'Myingyan',64,'Myanmar'),
  (9,'53 Idfu Parkway',361,'Nantou',92,'Taiwan'),
  (10,'1795 Santiago Way',295,'Laredo',103,'United States');
UNLOCK TABLES;

SET FOREIGN_KEY_CHECKS=1;
