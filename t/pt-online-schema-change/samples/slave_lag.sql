DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

DROP TABLE IF EXISTS `test`.`pt178_dummy`;

CREATE TABLE `pt178_dummy` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  f1 VARCHAR(30) NULL,
  f2 BIGINT(11) DEFAULT 0,
  PRIMARY KEY(id)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS `pt178`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `pt178` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  f1 VARCHAR(30) DEFAULT '',
  f2 BIGINT(11) DEFAULT 0,
  PRIMARY KEY(id)
) ENGINE=InnoDB;
