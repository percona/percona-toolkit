DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

DROP TABLE IF EXISTS `pt1717`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `pt1717` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  f1 VARCHAR(30) DEFAULT '',
  f2 BIGINT(11) DEFAULT 0,
  PRIMARY KEY(id),
  KEY(f2),
  KEY(f1, f2)
) ENGINE=InnoDB;
