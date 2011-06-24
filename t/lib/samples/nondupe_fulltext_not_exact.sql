CREATE TABLE `ft_not_dupe_key` (
  `a` varchar(64) default NULL,
  `b` varchar(65) default NULL,
  FULLTEXT KEY `ft_idx_a_b` (`a`,`b`),
  FULLTEXT KEY `ft_idx_b` (`b`),
  FULLTEXT KEY `ft_idx_a` (`a`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
