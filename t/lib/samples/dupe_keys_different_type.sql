CREATE TABLE `dupe_key` (
  `a` int(11) default NULL,
  `b` int(11) default NULL,
  `c` int(11) default NULL,
  KEY `a` (`a`),
  KEY `a_2` (`a`,`b`),
  KEY `a_3` (`a`,`b`),
) ENGINE=MyISAM DEFAULT CHARSET=latin1
