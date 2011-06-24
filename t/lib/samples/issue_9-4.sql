CREATE TABLE `issue_9` (
  `a` int(11) default NULL,
  `b` int(11) default NULL,
  PRIMARY KEY  (`a`,`b`),
  KEY `j` (`a`,`b`)
) ENGINE=MyISAM
