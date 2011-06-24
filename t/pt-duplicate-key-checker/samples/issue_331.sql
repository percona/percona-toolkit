DROP DATABASE IF EXISTS issue_331;
CREATE DATABASE issue_331;
USE issue_331;

DROP TABLE IF EXISTS `issue_331_t1`;
CREATE TABLE `issue_331_t1` (
  `t1_id` bigint(20) NOT NULL default '0',
  `bar` bigint(20) NOT NULL default '0',
  PRIMARY KEY  (`t1_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DROP TABLE IF EXISTS `issue_331_t2`;
CREATE TABLE `issue_331_t2` (
  `id` bigint(20) NOT NULL default '0',
  `foo` bigint(20) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  CONSTRAINT `fk_1` FOREIGN KEY (`id`) REFERENCES `issue_331_t1` (`t1_id`),
  CONSTRAINT `fk_2` FOREIGN KEY (`id`) REFERENCES `issue_331_t1` (`t1_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
