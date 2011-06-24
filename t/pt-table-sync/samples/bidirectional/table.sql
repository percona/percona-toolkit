drop database if exists bidi;
create database bidi;
use bidi;
CREATE TABLE `t` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `c`  varchar(255) default NULL,
  `d`  int(1) unsigned NOT NULL default 0,
  `ts` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`id`),
  KEY `ts` (`ts`)
) ENGINE=InnoDB;
