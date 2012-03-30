drop database if exists ca;
create database ca;
use ca;
CREATE TABLE `interval_lmp_rt_5min` (
  `datetime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `avg` float DEFAULT NULL,
  `median` float DEFAULT NULL,
  `reference` float DEFAULT NULL,
  `interpolated` tinyint(3) unsigned DEFAULT '0',
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`datetime`),
  KEY `interval_lmp_rt_5min_timestamp_idx` (`timestamp`)
) ENGINE=InnoDB;

CREATE TABLE `lmp_rt_5min` (
  `datetime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `handle_node_lmp` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `lmp` float DEFAULT NULL,
  `congestion` float DEFAULT NULL,
  `loss` float DEFAULT NULL,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `interpolated` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`datetime`,`handle_node_lmp`),
  KEY `lmp_rt_5min_handle_node_lmp_idxfk` (`handle_node_lmp`),
  KEY `lmp_rt_5min_timestamp_idx` (`timestamp`)
) ENGINE=InnoDB;
