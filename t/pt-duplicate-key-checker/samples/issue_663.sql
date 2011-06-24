DROP DATABASE IF EXISTS issue_663;
CREATE DATABASE issue_663;
USE issue_663;
CREATE TABLE `t` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `trx_id` int(10) unsigned default NULL,
  `dTime` datetime NOT NULL,
  `xmlerror` text,
  PRIMARY KEY (`id`),
  KEY `idx1` (`trx_id`),
  KEY `idx2` (`trx_id`, `xmlerror`(128), `dTime`)
) ENGINE=MyISAM;
