DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE `season_pk_historties_60` (
`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
`season_tagid` varchar(200) NOT NULL,
`subject_id` bigint(20) DEFAULT NULL,
`account_id` bigint(20) unsigned NOT NULL,
`pk_result` text NOT NULL,
`created_at` datetime DEFAULT NULL,
`schedule_tag_id` varchar(200) DEFAULT '',
`schedule_type` int(11) NOT NULL DEFAULT '0' COMMENT '赛程类型',
PRIMARY KEY (`id`),
KEY `idx_account` (`account_id`),
KEY `idx_created_at` (`created_at`),
KEY `idx_season` (`season_tagid`),
KEY `idx_season_subject_account` (`season_tagid`,`subject_id`,`account_id`),
KEY `idx_schedule_subject_account` (`schedule_tag_id`,`subject_id`,`account_id`),
KEY `idx_account_subject_schedule_type` (`account_id`,`subject_id`,`schedule_type`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8mb4;
