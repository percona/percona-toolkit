-- MySQL dump 10.13  Distrib 5.7.13-6, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: test
-- ------------------------------------------------------
-- Server version	5.7.13-6-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `o1`
--

DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

DROP TABLE IF EXISTS `o1`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `o1` (
  `org_id` char(20) NOT NULL,
  `instance_id` char(20) NOT NULL,
  `feature` enum('FOO','BAR','BAZ','CAT','DOG','DERP','HERP','VANILLA','CHOCOLATE','MINT') NOT NULL DEFAULT 'FOO',
  `is_supported` bit(1) NOT NULL,
  `is_enabled` bit(1) NOT NULL,
  `c2` int(11) DEFAULT NULL,
  PRIMARY KEY (`instance_id`,`feature`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `o1`
--

LOCK TABLES `o1` WRITE;
/*!40000 ALTER TABLE `o1` DISABLE KEYS */;
INSERT INTO `o1` VALUES ('a','00000000','FOO','','',NULL),('a','00000000','BAR','','',NULL),('a','00000000','BAZ','','',NULL),('a','00000000','CAT','','',NULL),('a','00000000','DOG','','',NULL),('a','00000000','DERP','','',NULL),('a','00000000','HERP','','',NULL),('a','00000000','VANILLA','','',NULL),('a','00000000','CHOCOLATE','','',NULL),('a','00000000','MINT','','',NULL),('a','00000001','FOO','','',NULL),('a','00000001','BAR','','',NULL),('a','00000001','BAZ','','',NULL),('a','00000001','CAT','','',NULL),('a','00000001','DOG','','',NULL),('a','00000001','DERP','','',NULL),('a','00000001','HERP','','',NULL),('a','00000001','VANILLA','','',NULL),('a','00000001','CHOCOLATE','','',NULL),('a','00000001','MINT','','',NULL),('a','00000002','FOO','','',NULL),('a','00000002','BAR','','',NULL),('a','00000002','BAZ','','',NULL),('a','00000002','CAT','','',NULL),('a','00000002','DOG','','',NULL),('a','00000002','DERP','','',NULL),('a','00000002','HERP','','',NULL),('a','00000002','VANILLA','','',NULL),('a','00000002','CHOCOLATE','','',NULL),('a','00000002','MINT','','',NULL),('a','00000003','FOO','','',NULL),('a','00000003','BAR','','',NULL),('a','00000003','BAZ','','',NULL),('a','00000003','CAT','','',NULL),('a','00000003','DOG','','',NULL),('a','00000003','DERP','','',NULL),('a','00000003','HERP','','',NULL),('a','00000003','VANILLA','','',NULL),('a','00000003','CHOCOLATE','','',NULL),('a','00000003','MINT','','',NULL),('a','00000004','FOO','','',NULL),('a','00000004','BAR','','',NULL),('a','00000004','BAZ','','',NULL),('a','00000004','CAT','','',NULL),('a','00000004','DOG','','',NULL),('a','00000004','DERP','','',NULL),('a','00000004','HERP','','',NULL),('a','00000004','VANILLA','','',NULL),('a','00000004','CHOCOLATE','','',NULL),('a','00000004','MINT','','',NULL),('a','00000005','FOO','','',NULL),('a','00000005','BAR','','',NULL),('a','00000005','BAZ','','',NULL),('a','00000005','CAT','','',NULL),('a','00000005','DOG','','',NULL),('a','00000005','DERP','','',NULL),('a','00000005','HERP','','',NULL),('a','00000005','VANILLA','','',NULL),('a','00000005','CHOCOLATE','','',NULL),('a','00000005','MINT','','',NULL),('a','00000006','FOO','','',NULL),('a','00000006','BAR','','',NULL),('a','00000006','BAZ','','',NULL),('a','00000006','CAT','','',NULL),('a','00000006','DOG','','',NULL),('a','00000006','DERP','','',NULL),('a','00000006','HERP','','',NULL),('a','00000006','VANILLA','','',NULL),('a','00000006','CHOCOLATE','','',NULL),('a','00000006','MINT','','',NULL),('a','00000007','FOO','','',NULL),('a','00000007','BAR','','',NULL),('a','00000007','BAZ','','',NULL),('a','00000007','CAT','','',NULL),('a','00000007','DOG','','',NULL),('a','00000007','DERP','','',NULL),('a','00000007','HERP','','',NULL),('a','00000007','VANILLA','','',NULL),('a','00000007','CHOCOLATE','','',NULL),('a','00000007','MINT','','',NULL),('a','00000008','FOO','','',NULL),('a','00000008','BAR','','',NULL),('a','00000008','BAZ','','',NULL),('a','00000008','CAT','','',NULL),('a','00000008','DOG','','',NULL),('a','00000008','DERP','','',NULL),('a','00000008','HERP','','',NULL),('a','00000008','VANILLA','','',NULL),('a','00000008','CHOCOLATE','','',NULL),('a','00000008','MINT','','',NULL),('a','00000009','FOO','','',NULL),('a','00000009','BAR','','',NULL),('a','00000009','BAZ','','',NULL),('a','00000009','CAT','','',NULL),('a','00000009','DOG','','',NULL),('a','00000009','DERP','','',NULL),('a','00000009','HERP','','',NULL),('a','00000009','VANILLA','','',NULL),('a','00000009','CHOCOLATE','','',NULL),('a','00000009','MINT','','',NULL);
/*!40000 ALTER TABLE `o1` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2016-08-21 20:36:57
