drop database if exists test1171653;
create database test1171653;
use test1171653;

CREATE TABLE `t` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `foo` varchar(30) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `t` VALUES (1,'bar'), (2,'bar2'), (3,'bar3');
