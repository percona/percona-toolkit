CREATE TABLE `a` (
  `id` int(11) default NULL,
  `name` varchar(20) default NULL,
  UNIQUE KEY `id` (`id`),
  UNIQUE KEY `id_name` (`id`,`name`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
