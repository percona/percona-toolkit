CREATE TABLE `dupe_key` (
  `a` int(11) default NULL,
  `b` int(11) default NULL,
  KEY `a` (`a`),
  CONSTRAINT `t1_ibfk_1` FOREIGN KEY (`a`, `b`) REFERENCES `t2` (`a`, `b`),
  CONSTRAINT `t1_ibfk_2` FOREIGN KEY (`b`, `a`) REFERENCES `t2` (`b`, `a`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
