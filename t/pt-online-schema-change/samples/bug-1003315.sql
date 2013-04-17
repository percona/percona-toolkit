drop database if exists test1003315;
create database test1003315;
use test1003315;

DROP TABLE IF EXISTS `B`;
DROP TABLE IF EXISTS `A`;
CREATE TABLE `A` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `foo` varchar(30) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `B`;
CREATE TABLE `B` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `a` int(11) NOT NULL,
  KEY `9dde1f34` (`a`),
  PRIMARY KEY (`id`),
  CONSTRAINT `6970ddb42bec57fc` FOREIGN KEY (`a`) REFERENCES `A` (`id`)
) ENGINE=InnoDB;

INSERT INTO `A` VALUES (1,'bar'), (2,'bar2'), (3,'bar3');
INSERT INTO `B` VALUES (1, 1), (2, 2), (3, 1);
