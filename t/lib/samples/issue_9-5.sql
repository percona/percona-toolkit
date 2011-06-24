CREATE TABLE `issue_9` (
  `a` int(11) default NULL,
  `b` int(11) default NULL,
  UNIQUE KEY `i` (`a`,`b`),
  UNIQUE KEY `j` (`a`)
) ENGINE=MyISAM
