CREATE TABLE `t` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `a` varchar(200) DEFAULT NULL,
  `b` decimal(22,0) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `b` (`b`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
