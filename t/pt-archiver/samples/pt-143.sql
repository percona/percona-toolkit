DROP SCHEMA IF EXISTS test;
CREATE SCHEMA test;

CREATE TABLE test.`stats_r` (
`id` int(10) unsigned NOT NULL,
`end` datetime NOT NULL,
`start` datetime NOT NULL,
`sum_value` float DEFAULT NULL,
`user_id` varchar(100) NOT NULL DEFAULT '',
`interval` int(10) unsigned NOT NULL DEFAULT '0',
`mean` float DEFAULT NULL,
`max` float DEFAULT NULL,
`min` float DEFAULT NULL,
PRIMARY KEY (`id`,`start`,`end`,`user_id`(13),`interval`),
KEY `cid_start_end` (`user_id`(13),`start`,`end`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE test.stats_s LIKE test.stats_r;

INSERT INTO `test`.`stats_r`
(`id`,`end`,`start`,`sum_value`,`user_id`,`interval`,`mean`,`max`,`min`)
VALUES
(1,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(2,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(3,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(4,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(5,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(6,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(7,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(8,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(9,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1),
(10,now() + INTERVAL 1 hour, NOW(), 1,1,1,1,1,1);

