DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;
CREATE TABLE `multi_resource_apt` (
  `apt_id` int(10) unsigned NOT NULL DEFAULT '0',
  `res_id` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`apt_id`,`res_id`),
  KEY `resid` (`res_id`)
) ENGINE=InnoDB;
INSERT INTO multi_resource_apt VALUES
  (1, 1),
  (2, 1),
  (2, 2),
  (3, 1),
  (3, 2),
  (3, 3),
  (4, 1),
  (4, 2),
  (4, 3),
  (4, 4);
