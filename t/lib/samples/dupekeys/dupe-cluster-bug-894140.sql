CREATE TABLE `bug_894140` (
  `row_id` bigint(20) NOT NULL AUTO_INCREMENT,
  `player_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`row_id`),
  UNIQUE KEY `row_id` (`row_id`),
  UNIQUE KEY `player_id` (`player_id`),
  KEY `player_id_2` (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
