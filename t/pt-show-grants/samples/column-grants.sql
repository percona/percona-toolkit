drop database if exists test;
create database test;
use test;

CREATE TABLE t (
  `SOrNum` mediumint(9) unsigned NOT NULL auto_increment,
  `SPNum` mediumint(9) unsigned NOT NULL,
  `DateCreated` timestamp NOT NULL default CURRENT_TIMESTAMP,
  `DateRelease` timestamp NOT NULL default '0000-00-00 00:00:00',
  `ActualReleasedDate` timestamp NULL default NULL,
  `PckPrice` decimal(10,2) NOT NULL default '0.00',
  `Status` varchar(20) NOT NULL,
  `PaymentStat` varchar(20) NOT NULL default 'Unpaid',
  `CusCode` int(9) unsigned NOT NULL,
  `SANumber` mediumint(9) unsigned NOT NULL default '0',
  `SpecialInstruction` varchar(500) default NULL,
  PRIMARY KEY (`SOrNum`)
) ENGINE=InnoDB;
