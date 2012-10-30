DROP DATABASE IF EXISTS bug_1047335;
CREATE DATABASE bug_1047335;
USE bug_1047335;
CREATE TABLE bug_1047335.crashed_table (
   `id` int(10) unsigned NOT NULL auto_increment,
   `trx_id` int(10) unsigned default NULL,
   `etc` text,
   PRIMARY KEY (`id`),
   KEY `idx1` (`trx_id`),
   KEY `idx2` (`trx_id`, `etc`(128))
) ENGINE=MyISAM;
