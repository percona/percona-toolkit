CREATE TABLE `foo` (
  `a` int(11) NOT NULL,
  `b` int(11) default NULL,
  PRIMARY KEY  (`a`),
  KEY `b` (`b`,`a`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
