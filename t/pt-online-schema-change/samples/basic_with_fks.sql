DROP DATABASE IF EXISTS pt_osc;
CREATE DATABASE pt_osc;
USE pt_osc;

SET foreign_key_checks=0;

CREATE TABLE `country` (
  `country_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `country` varchar(50) NOT NULL,
  `last_update` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`country_id`)
) ENGINE=InnoDB;

CREATE TABLE `city` (
  `city_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `city` varchar(50) NOT NULL,
  `country_id` smallint(5) unsigned NOT NULL,
  `last_update` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`city_id`),
  KEY `idx_fk_country_id` (`country_id`),
  CONSTRAINT `fk_city_country` FOREIGN KEY (`country_id`) REFERENCES `country` (`country_id`) ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE `address` (
  `address_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `address` varchar(50) NOT NULL,
  `city_id` smallint(5) unsigned NOT NULL,
  `postal_code` varchar(10) DEFAULT NULL,
  `last_update` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`address_id`),
  KEY `idx_fk_city_id` (`city_id`),
  CONSTRAINT `fk_address_city` FOREIGN KEY (`city_id`) REFERENCES `city` (`city_id`) ON UPDATE CASCADE
) ENGINE=InnoDB;

INSERT INTO pt_osc.country VALUES
  (1, 'Canada', null),
  (2, 'USA',    null),
  (3, 'Mexico', null),
  (4, 'France', null),
  (5, 'Spain',  null);

INSERT INTO pt_osc.city VALUES
  (null, 'Montréal', 1, null),
  (null, 'New York', 2, null),
  (null, 'Durango',  3, null),
  (null, 'Paris',    4, null),
  (null, 'Madrid',   5, null);

INSERT INTO pt_osc.address VALUES
  (null, 'addy 1', 1, '10000', null),
  (null, 'addy 2', 2, '20000', null),
  (null, 'addy 3', 3, '30000', null),
  (null, 'addy 4', 4, '40000', null),
  (null, 'addy 5', 5, '50000', null);

SET foreign_key_checks=1;
