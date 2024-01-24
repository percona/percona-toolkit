DROP DATABASE IF EXISTS test;
CREATE DATABASE test;

CREATE TABLE `test`.`t1` (
  `c1` int(10) unsigned NOT NULL,
  `c2` varchar(255) NOT NULL,
  `Last_referenced` INT NOT NULL DEFAULT 0,
  `c3` int(10) unsigned NOT NULL,
  `c4` int(10) unsigned NOT NULL DEFAULT '0',
  `c5` varchar(255) NOT NULL DEFAULT '',
  `c6` varchar(255) NOT NULL DEFAULT '',
  `c7` varchar(255) NOT NULL DEFAULT '',
  `c8` varchar(255) DEFAULT '',
  `c9` varchar(255) DEFAULT '',
  `c10` int(10) NOT NULL DEFAULT '0',
  PRIMARY KEY (`c1`,`c2`),
  KEY `Last_Referenced_c6_Index` (`Last_referenced`,`c6`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO `test`.`t1` VALUES 
 (1,'',0,139772,47473,'','','','','',178332),
 (2,'',1,74283,65463,'','','','','',159673),
 (3,'',2,161929,72681,'','','','','',189530),
 (4,'',3,76402,136494,'','','','','',132035),
 (5,'',4,133053,176778,'','','','','',198267),
 (6,'',5,68824,198479,'','','','','',139027),
 (7,'',6,98103,195314,'','','','','',307),
 (8,'',7,15094,53330,'','','','','',26258),
 (9,'',8,183263,73658,'','','','','',51367),
(10,'',9,141835,87261,'','','','','',73928);



