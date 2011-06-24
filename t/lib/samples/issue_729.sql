CREATE TABLE `posts` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `template_id` smallint(5) unsigned NOT NULL DEFAULT '0',
  `other_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `date` int(10) unsigned NOT NULL DEFAULT '0',
  `private` tinyint(3) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `other_id` (`other_id`)
) ENGINE=InnoDB AUTO_INCREMENT=15417 DEFAULT CHARSET=latin1;
