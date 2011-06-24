--
-- Host: localhost    Database: test
-- ------------------------------------------------------
-- Server version	5.1.53-log

DROP TABLE IF EXISTS `denorm_items`;
CREATE TABLE `denorm_items` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` varchar(16) DEFAULT NULL,
  `color` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM AUTO_INCREMENT=7 DEFAULT CHARSET=latin1;

LOCK TABLES `denorm_items` WRITE;
INSERT INTO `denorm_items` VALUES (1,'t1','red'),(2,'t2','red'),(3,'t2','blue'),(4,'t3','black'),(5,'t4','orange'),(6,'t5','green');
UNLOCK TABLES;

DROP TABLE IF EXISTS `types`;
CREATE TABLE `types` (
  `type_id` int(11) NOT NULL AUTO_INCREMENT,
  `type` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DROP TABLE IF EXISTS `colors`;
CREATE TABLE `colors` (
  `color_id` int(11) NOT NULL AUTO_INCREMENT,
  `color` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`color_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DROP TABLE IF EXISTS `items`;
CREATE TABLE `items` (
  `item_id` int(11) NOT NULL AUTO_INCREMENT,
  `type_id` int(11) NOT NULL,
  `color_id` int(11) NOT NULL,
  PRIMARY KEY (`item_id`),
  KEY `type_id` (`type_id`),
  KEY `color_id` (`color_id`),
  CONSTRAINT `items_ibfk_1` FOREIGN KEY (`type_id`) REFERENCES `types` (`type_id`) ON UPDATE CASCADE,
  CONSTRAINT `items_ibfk_2` FOREIGN KEY (`color_id`) REFERENCES `colors` (`color_id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
