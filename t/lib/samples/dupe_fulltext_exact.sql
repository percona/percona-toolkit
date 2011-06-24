CREATE TABLE `ft_dupe_key_exact` (
  `a` varchar(16) default NULL,
  `b` varchar(16) default NULL,
  FULLTEXT KEY `ft_idx_a_b_1` (`a`,`b`),
  FULLTEXT KEY `ft_idx_a_b_2` (`a`,`b`)
) ENGINE=MyISAM DEFAULT CHARSET=latin
