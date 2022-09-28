DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `test_a` (
`test_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
`column_a` varchar(80) DEFAULT NULL,
`column_b` varchar(20) DEFAULT NULL,
`active` tinyint(1) unsigned DEFAULT NULL,
`created` timestamp NULL DEFAULT NULL,
`modified` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
PRIMARY KEY (`test_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

