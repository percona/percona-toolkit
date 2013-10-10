DROP DATABASE IF EXISTS sync_float_1229861;
CREATE DATABASE sync_float_1229861;
USE sync_float_1229861;
CREATE TABLE `t` (
  `c1` int(10) DEFAULT NULL,
  `c2` int(10) DEFAULT NULL,
  `c3` int(10) DEFAULT NULL,
  `snrmin` float(3,1) DEFAULT NULL,
  `snrmax` float(3,1) DEFAULT NULL,
  `snravg` float(3,1) DEFAULT NULL,
  KEY `c2` (`c2`,`c3`)
) ENGINE=InnoDB;
