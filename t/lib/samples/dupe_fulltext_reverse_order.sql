CREATE TABLE `ft_dupe_key_reverse_order` (
  `a` varchar(16) default NULL,
  `b` varchar(16) default NULL,
  FULLTEXT KEY `ft_idx_a_b` (`a`,`b`),
  FULLTEXT KEY `ft_idx_b_a` (`b`,`a`)
) ENGINE=MyISAM DEFAULT CHARSET=latin
