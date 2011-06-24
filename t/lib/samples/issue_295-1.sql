CREATE TABLE `issue_295` (
  `a` int(11) NOT NULL,
  `b` int(11) NOT NULL,
  UNIQUE KEY `i` (`a`),
  KEY `j` (`a`,`b`)
) ENGINE=InnoDB
