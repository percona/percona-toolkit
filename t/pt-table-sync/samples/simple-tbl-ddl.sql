CREATE TABLE `it1` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `a` int(11) NOT NULL,
  `b` int(11) NOT NULL,
  `c` varchar(16) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `c` (`c`),
  UNIQUE KEY `id` (`id`,`c`),
  KEY `a` (`a`)
) ENGINE=InnoDB
