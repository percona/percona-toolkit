DROP TABLE IF EXISTS `messages`;
CREATE TABLE `messages` (
  `MID` int(20) NOT NULL default '0',
  `TID` bigint(20) NOT NULL default '0',
  `AUTHOR` varchar(32) NOT NULL default '',
  `DATE` datetime NOT NULL default '0000-00-00 00:00:00',
  `INTERNAL` char(1) NOT NULL default '0',
  `ISOPER` char(1) NOT NULL default '0',
  `HEADERS` text NOT NULL,
  `MSG` text NOT NULL,
  PRIMARY KEY (`MID`),
  UNIQUE KEY `ID` (`MID`),
  KEY `TID` (`TID`)
) ENGINE=MyISAM;
