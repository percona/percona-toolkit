CREATE TABLE `innodb_dupe` (
  `a` int(11) NOT NULL,
  `b` int(11) default NULL,
  PRIMARY KEY  (`a`),
  KEY `b` (`b`,`a`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
