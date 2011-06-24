CREATE TABLE `issue_9` (
  `a` int(11) default NULL,
  `b` int(11) default NULL,
  `c` int(11) default NULL,
  PRIMARY KEY  (`a`),
  UNIQUE KEY `ua_b` (`a`,`b`),
  KEY `a_b_c` (`a`,`b`,`c`)
) ENGINE=MyISAM
