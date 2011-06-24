CREATE TABLE `foo` (
  `id` int(11) NOT NULL auto_increment,
  `first, last` varchar(32) default NULL,
  PRIMARY KEY  (`id`),
  KEY `nameindex` (`first, last`)
) ENGINE=MyISAM
