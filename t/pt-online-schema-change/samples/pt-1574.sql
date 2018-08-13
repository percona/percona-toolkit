DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `test`.`t1` (
`id` int(11) DEFAULT NULL,
`site_name` varchar(25) DEFAULT NULL,
`last_update` datetime DEFAULT NULL,
UNIQUE KEY `idx_id` (`id`),
KEY `idx_last_update` (`last_update`),
KEY `idx_site_name` (`site_name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO `test`.`t1` VALUES 
(1385108873,'Carolyn Ryan','2018-01-13 17:05:24'),
(2140660022,'Patricia Garza','2018-01-13 19:07:51'),
(1473481373,'Rachel George','2017-12-05 21:09:53'),
(1394124308,'Mrs. Ms. Miss Janet Dixon','2017-10-28 07:07:41'),
(1978918050,'Louis Gray Jr. Sr. I II I','2017-11-01 22:10:39'),
(1275940242,'Lois Spencer','2018-02-22 01:01:38'),
(NULL,NULL,NULL),
(NULL,NULL,NULL);


CREATE TABLE `t2` (
  `id` int(11) DEFAULT NULL,
  `site_name` varchar(25) NOT NULL,
  `last_update` datetime DEFAULT NULL,
  PRIMARY KEY (`site_name`),
  UNIQUE KEY `idx_id` (`id`),
  KEY `idx_last_update` (`last_update`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO `test`.`t2` VALUES 
(1385108873,'Carolyn Ryan','2018-01-13 17:05:24'),
(2140660022,'Patricia Garza','2018-01-13 19:07:51'),
(1473481373,'Rachel George','2017-12-05 21:09:53'),
(1394124308,'Mrs. Ms. Miss Janet Dixon','2017-10-28 07:07:41'),
(1978918050,'Louis Gray Jr. Sr. I II I','2017-11-01 22:10:39'),
(1275940242,'Lois Spencer','2018-02-22 01:01:38'),
(NULL,"aaa",NULL);
