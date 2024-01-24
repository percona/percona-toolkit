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

INSERT INTO pt_osc.country (`country_id`, `country`) VALUES
  (1, 'Canada'),
  (2, 'USA'),
  (3, 'Mexico'),
  (4, 'France'),
  (5, 'Spain');

INSERT INTO pt_osc.city (`city_id`, `city`, `country_id`) VALUES
  (1, 'Montréal', 1),
  (2, 'New York', 2),
  (3, 'Durango',  3),
  (4, 'Paris',    4),
  (5, 'Madrid',   5);

INSERT INTO pt_osc.address (`address_id`, `address`, `city_id`, `postal_code`) VALUES
  (1, 'addy 1', 1, '10000'),
  (2, 'addy 2', 2, '20000'),
  (3, 'addy 3', 3, '30000'),
  (4, 'addy 4', 4, '40000'),
  (5, 'addy 5', 5, '50000');

SET foreign_key_checks=1;
