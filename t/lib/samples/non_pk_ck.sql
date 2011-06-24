CREATE TABLE `t` (
  `i` int(11) NOT NULL,
  `j` int(11) default NULL,
  UNIQUE KEY `j_idx` (`j`),
  UNIQUE KEY `i_j_idx` (`i`,`j`),
  UNIQUE KEY `i_idx` (`i`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
