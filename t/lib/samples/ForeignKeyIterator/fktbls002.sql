--
-- Database: test
--

--        
-- data
-- |
-- +--> data_report
-- |
-- +--> entity
--

CREATE TABLE `data_report` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `date` date DEFAULT NULL,
  `posted` datetime DEFAULT NULL,
  `acquired` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `date` (`date`,`posted`,`acquired`)
) ENGINE=InnoDB;

CREATE TABLE `entity` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `entity_property_1` varchar(16) DEFAULT NULL,
  `entity_property_2` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `entity_property_1` (`entity_property_1`,`entity_property_2`)
) ENGINE=InnoDB;

CREATE TABLE `data` (
  `data_report` int(11) NOT NULL DEFAULT '0',
  `hour` tinyint(4) NOT NULL DEFAULT '0',
  `entity` int(11) NOT NULL DEFAULT '0',
  `data_1` varchar(16) DEFAULT NULL,
  `data_2` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`data_report`,`hour`,`entity`),
  KEY `entity` (`entity`),
  CONSTRAINT `data_ibfk_1` FOREIGN KEY (`data_report`) REFERENCES `data_report` (`id`),
  CONSTRAINT `data_ibfk_2` FOREIGN KEY (`entity`) REFERENCES `entity` (`id`)
) ENGINE=InnoDB;
