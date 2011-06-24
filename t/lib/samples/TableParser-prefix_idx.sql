CREATE TABLE `t1` (
  `a` varchar(64) default NULL,
  `b` varchar(64) default NULL,
  KEY `prefix_idx` (`a`(10),`b`(20)),
  KEY `mix_idx` (`a`,`b`(20))
) ENGINE=MyISAM DEFAULT CHARSET=latin1
