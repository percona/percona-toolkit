CREATE TABLE `dupe_key` (
  `a` int(11) default NULL,
  `b` int(11) default NULL,
  `c` int(11) default NULL,
  KEY `a_2` (`a`,`b`),
  KEY `a` (`a`),
) ENGINE=MyISAM DEFAULT CHARSET=latin1
