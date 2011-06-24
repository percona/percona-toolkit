CREATE TABLE `t1` (
  `a` int(11) NOT NULL,
  `b` char(50) default NULL,
  KEY `a` (`a`),
  CONSTRAINT `t1_ibfk_1` FOREIGN KEY (`a`) REFERENCES `t2` (`a`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
