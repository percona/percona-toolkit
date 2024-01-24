-- MySQL dump 10.13  Distrib 5.7.18, for Linux (x86_64)
--
-- Host: 127.1    Database: percona
-- ------------------------------------------------------
-- Server version	5.7.18-log

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
-- Table structure for table `checksums`
--
DROP DATABASE IF EXISTS percona;
CREATE DATABASE IF NOT EXISTS percona;

USE percona;

DROP TABLE IF EXISTS `checksums`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `checksums` (
  `db` char(64) NOT NULL,
  `tbl` char(64) NOT NULL,
  `chunk` int(11) NOT NULL,
  `chunk_time` float DEFAULT NULL,
  `chunk_index` varchar(200) DEFAULT NULL,
  `lower_boundary` text,
  `upper_boundary` text,
  `this_crc` char(40) NOT NULL,
  `this_cnt` int(11) NOT NULL,
  `master_crc` char(40) DEFAULT NULL,
  `master_cnt` int(11) DEFAULT NULL,
  `ts` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`db`,`tbl`,`chunk`),
  KEY `ts_db_tbl` (`ts`,`db`,`tbl`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `checksums`
--

LOCK TABLES `checksums` WRITE;
/*!40000 ALTER TABLE `checksums` DISABLE KEYS */;
INSERT INTO `checksums` VALUES ('fake_db','checksums',1,0.000297,NULL,NULL,NULL,'d8b8e420',23,'d8b8e420',23,'2017-07-18 08:25:33'),('fake_db','load_data',1,0.000285,NULL,NULL,NULL,'42981178',1,'42981178',1,'2017-07-18 08:25:33'),('fake_db','sentinel',1,0.000294,NULL,NULL,NULL,'8bbdd2c',1,'8bbdd2c',1,'2017-07-18 08:25:33'),('mysql','columns_priv',1,0.000245,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:32'),('mysql','db',1,0.000238,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:32'),('mysql','engine_cost',1,0.000302,NULL,NULL,NULL,'343e658a',2,'343e658a',2,'2017-07-18 08:25:32'),('mysql','event',1,0.000249,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:32'),('mysql','func',1,0.000251,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:32'),('mysql','help_category',1,0.000289,NULL,NULL,NULL,'55da20fe',40,'55da20fe',40,'2017-07-18 08:25:32'),('mysql','help_keyword',1,0.000625,NULL,NULL,NULL,'7d8bbf2c',682,'7d8bbf2c',682,'2017-07-18 08:25:32'),('mysql','help_relation',1,0.000924,NULL,NULL,NULL,'a656850f',1340,'a656850f',1340,'2017-07-18 08:25:32'),('mysql','help_topic',1,0.008071,NULL,NULL,NULL,'6a9bafa9',637,'6a9bafa9',637,'2017-07-18 08:25:33'),('mysql','ndb_binlog_index',1,0.000896,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','plugin',1,0.001212,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','proc',1,0.000408,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','procs_priv',1,0.000271,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','proxies_priv',1,0.000253,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','servers',1,0.000293,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','server_cost',1,0.00029,NULL,NULL,NULL,'3041ab5b',6,'3041ab5b',6,'2017-07-18 08:25:33'),('mysql','tables_priv',1,0.000211,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','time_zone',1,0.000242,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','time_zone_leap_second',1,0.000329,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','time_zone_name',1,0.00027,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','time_zone_transition',1,0.000247,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','time_zone_transition_type',1,0.000237,NULL,NULL,NULL,'0',0,'0',0,'2017-07-18 08:25:33'),('mysql','user',1,0.000386,NULL,NULL,NULL,'ab6ccd20',2,'ab6ccd20',2,'2017-07-18 08:25:33'),('percona_test','checksums',1,0.000297,NULL,NULL,NULL,'d8b8e420',23,'d8b8e420',23,'2017-07-18 08:25:33'),('percona_test','load_data',1,0.000285,NULL,NULL,NULL,'42981178',1,'42981178',1,'2017-07-18 08:25:33'),('percona_test','sentinel',1,0.000294,NULL,NULL,NULL,'8bbdd2c',1,'8bbdd2c',1,'2017-07-18 08:25:33'),('sakila','actor',1,0.000411,NULL,NULL,NULL,'6816983c',200,'6816983c',200,'2017-07-18 08:25:33'),('sakila','address',1,0.001221,NULL,NULL,NULL,'ad975fe4',603,'ad975fe4',603,'2017-07-18 08:25:33'),('sakila','category',1,0.001169,NULL,NULL,NULL,'9c52e409',16,'9c52e409',16,'2017-07-18 08:25:33'),('sakila','city',1,0.002102,NULL,NULL,NULL,'4d700c4',600,'4d700c4',600,'2017-07-18 08:25:33'),('sakila','country',1,0.000379,NULL,NULL,NULL,'14ed8b59',109,'14ed8b59',109,'2017-07-18 08:25:33'),('sakila','customer',1,0.001379,NULL,NULL,NULL,'87c13eb5',599,'87c13eb5',599,'2017-07-18 08:25:33'),('sakila','film',1,0.012602,NULL,NULL,NULL,'bb27da2e',1000,'bb27da2e',1000,'2017-07-18 08:25:34'),('sakila','film_actor',1,0.01618,NULL,NULL,NULL,'5f42e2be',5462,'5f42e2be',5462,'2017-07-18 08:25:34'),('sakila','film_category',1,0.002104,NULL,NULL,NULL,'1ff3be9a',1000,'1ff3be9a',1000,'2017-07-18 08:25:34'),('sakila','film_text',1,0.005167,NULL,NULL,NULL,'8c094796',1000,'8c094796',1000,'2017-07-18 08:25:34'),('sakila','inventory',1,0.015794,NULL,NULL,NULL,'58102314',4581,'58102314',4581,'2017-07-18 08:25:34'),('sakila','language',1,0.000297,NULL,NULL,NULL,'4a5f0378',6,'4a5f0378',6,'2017-07-18 08:25:35'),('sakila','payment',1,0.024087,NULL,NULL,NULL,'4b712aa1',16049,'4b712aa1',16049,'2017-07-18 08:25:35'),('sakila','rental',1,0.045657,NULL,NULL,NULL,'a4aead4b',16044,'a4aead4b',16044,'2017-07-18 08:25:35'),('sakila','staff',1,0.001195,NULL,NULL,NULL,'5facaa32',2,'5facaa32',2,'2017-07-18 08:25:35'),('sakila','store',1,0.001001,NULL,NULL,NULL,'223743d9',2,'223743d9',2,'2017-07-18 08:25:35'),('sys','sys_config',1,0.000442,NULL,NULL,NULL,'82cc7288',6,'82cc7288',6,'2017-07-18 08:25:35');
/*!40000 ALTER TABLE `checksums` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2017-07-18  5:27:15
