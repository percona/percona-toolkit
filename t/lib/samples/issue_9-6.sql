CREATE TABLE `issue_9` (
  `a` int(11) default NULL,
  `b` int(11) default NULL,
  `c` int(11) default NULL,
  KEY `a` (`a`),
  UNIQUE KEY `ua` (`a`),
  KEY `a_b` (`a`,`b`),
  PRIMARY KEY  (`a`,`b`),
  KEY `b_a` (`b`,`a`),
  UNIQUE KEY `uc_a_b` (`c`,`a`,`b`),
  KEY `c_b` (`c`,`b`),
  UNIQUE KEY `ub_c` (`b`,`c`),
  UNIQUE KEY `ua_b` (`a`,`b`),
  UNIQUE KEY `ua_b2` (`a`,`b`),
  KEY `a_b_c` (`a`,`b`,`c`)
) ENGINE=MyISAM
