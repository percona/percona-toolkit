CREATE TABLE `t` (
  `a` int(11) default NULL,
  `B` int(11) default NULL,
  `MixedCol` int(11) default NULL,
  KEY `MyKey` (`a`,`B`,`MixedCol`)
) ENGINE=MyISAM
