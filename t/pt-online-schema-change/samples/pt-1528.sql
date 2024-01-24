-- MySQL dump 10.13  Distrib 5.7.19-17, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: test
-- ------------------------------------------------------
-- Server version	5.7.19-17-log

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
/*!50717 SELECT COUNT(*) INTO @rocksdb_has_p_s_session_variables FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'performance_schema' AND TABLE_NAME = 'session_variables' */;
/*!50717 SET @rocksdb_get_is_supported = IF (@rocksdb_has_p_s_session_variables, 'SELECT COUNT(*) INTO @rocksdb_is_supported FROM performance_schema.session_variables WHERE VARIABLE_NAME=\'rocksdb_bulk_load\'', 'SELECT 0') */;
/*!50717 PREPARE s FROM @rocksdb_get_is_supported */;
/*!50717 EXECUTE s */;
/*!50717 DEALLOCATE PREPARE s */;
/*!50717 SET @rocksdb_enable_bulk_load = IF (@rocksdb_is_supported, 'SET SESSION rocksdb_bulk_load = 1', 'SET @rocksdb_dummy_bulk_load = 0') */;
/*!50717 PREPARE s FROM @rocksdb_enable_bulk_load */;
/*!50717 EXECUTE s */;
/*!50717 DEALLOCATE PREPARE s */;

--
-- Table structure for table `brokenutf8alter`
--

DROP DATABASE IF EXISTS test;
CREATE DATABASE test;

USE test;

DROP TABLE IF EXISTS `brokenutf8alter`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `brokenutf8alter` (
  `ID` binary(16) NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `brokenutf8alter`
--

LOCK TABLES `brokenutf8alter` WRITE;
/*!40000 ALTER TABLE `brokenutf8alter` DISABLE KEYS */;
INSERT INTO `brokenutf8alter` VALUES ('.SGı:\Ëä\ﬂB¨\0'),('.SK,:\Ëä\ﬂB¨\0'),('.SL_:\Ëä\ﬂB¨\0'),('.SL\‹:\Ëä\ﬂB¨\0'),('.SMB:\Ëä\ﬂB¨\0'),('.SMò:\Ëä\ﬂB¨\0'),('.SMÙ:\Ëä\ﬂB¨\0'),('.SOE:\Ëä\ﬂB¨\0'),('.SOÆ:\Ëä\ﬂB¨\0'),('.SP:\Ëä\ﬂB¨\0'),('.SPZ:\Ëä\ﬂB¨\0'),('.SP∞:\Ëä\ﬂB¨\0'),('.SQ:\Ëä\ﬂB¨\0'),('.SQX:\Ëä\ﬂB¨\0'),('.SQ©:\Ëä\ﬂB¨\0'),('.SQ˜:\Ëä\ﬂB¨\0'),('.SRK:\Ëä\ﬂB¨\0'),('.ST4:\Ëä\ﬂB¨\0'),('.SU=:\Ëä\ﬂB¨\0'),('.SUó:\Ëä\ﬂB¨\0'),('.SU:\Ëä\ﬂB¨\0'),('.SVC:\Ëä\ﬂB¨\0'),('.SVî:\Ëä\ﬂB¨\0'),('.SV\Â:\Ëä\ﬂB¨\0'),('.SW8:\Ëä\ﬂB¨\0'),('.SWá:\Ëä\ﬂB¨\0'),('.SX\“:\Ëä\ﬂB¨\0'),('.SY\":\Ëä\ﬂB¨\0'),('.SYr:\Ëä\ﬂB¨\0'),('.SY\¬:\Ëä\ﬂB¨\0'),('.SZ:\Ëä\ﬂB¨\0'),('.SZô:\Ëä\ﬂB¨\0'),('.S[):\Ëä\ﬂB¨\0'),('.S[∫:\Ëä\ﬂB¨\0'),('.S\\N:\Ëä\ﬂB¨\0'),('.S\\\·:\Ëä\ﬂB¨\0'),('.S]>:\Ëä\ﬂB¨\0'),('.S]é:\Ëä\ﬂB¨\0'),('.S]\ﬁ:\Ëä\ﬂB¨\0'),('.S^.:\Ëä\ﬂB¨\0'),('.S^:\Ëä\ﬂB¨\0'),('.S^\À:\Ëä\ﬂB¨\0'),('.S_8:\Ëä\ﬂB¨\0'),('.S_¿:\Ëä\ﬂB¨\0'),('.S`W:\Ëä\ﬂB¨\0'),('.S`Ò:\Ëä\ﬂB¨\0'),('.Sa~:\Ëä\ﬂB¨\0'),('.Sb:\Ëä\ﬂB¨\0'),('.Sb®:\Ëä\ﬂB¨\0'),('.Sc>:\Ëä\ﬂB¨\0'),('.Sc\»:\Ëä\ﬂB¨\0'),('.Sd:\Ëä\ﬂB¨\0'),('.Sdv:\Ëä\ﬂB¨\0'),('.Sd\√:\Ëä\ﬂB¨\0'),('.Se:\Ëä\ﬂB¨\0'),('.Seb:\Ëä\ﬂB¨\0'),('.Se∑:\Ëä\ﬂB¨\0'),('.Sf:\Ëä\ﬂB¨\0'),('.SfP:\Ëä\ﬂB¨\0'),('.Sfü:\Ëä\ﬂB¨\0'),('.SfÒ:\Ëä\ﬂB¨\0'),('.Sg?:\Ëä\ﬂB¨\0'),('.Sgò:\Ëä\ﬂB¨\0'),('.Sh:\Ëä\ﬂB¨\0'),('.Sh®:\Ëä\ﬂB¨\0'),('.Si7:\Ëä\ﬂB¨\0'),('.Si\‘:\Ëä\ﬂB¨\0'),('.Sji:\Ëä\ﬂB¨\0'),('.Sk:\Ëä\ﬂB¨\0'),('.Skâ:\Ëä\ﬂB¨\0'),('.Sk\‹:\Ëä\ﬂB¨\0'),('.Sl(:\Ëä\ﬂB¨\0'),('.Sl{:\Ëä\ﬂB¨\0'),('.Sl\…:\Ëä\ﬂB¨\0'),('.Sm\Z:\Ëä\ﬂB¨\0'),('.Smh:\Ëä\ﬂB¨\0'),('.Smª:\Ëä\ﬂB¨\0'),('.Sn:\Ëä\ﬂB¨\0'),('.So:\Ëä\ﬂB¨\0'),('.Sob:\Ëä\ﬂB¨\0'),('.So¥:\Ëä\ﬂB¨\0'),('.Sp:\Ëä\ﬂB¨\0'),('.SpQ:\Ëä\ﬂB¨\0'),('.Spù:\Ëä\ﬂB¨\0'),('.Sp:\Ëä\ﬂB¨\0'),('.SqA:\Ëä\ﬂB¨\0'),('.Sqê:\Ëä\ﬂB¨\0'),('.Sq\‹:\Ëä\ﬂB¨\0'),('.Sr+:\Ëä\ﬂB¨\0'),('.Srv:\Ëä\ﬂB¨\0'),('.Sr¡:\Ëä\ﬂB¨\0'),('.Ss:\Ëä\ﬂB¨\0'),('.Ss_:\Ëä\ﬂB¨\0'),('.St:\Ëä\ﬂB¨\0'),('.St :\Ëä\ﬂB¨\0'),('.St5:\Ëä\ﬂB¨\0'),('.StI:\Ëä\ﬂB¨\0'),('.St^:\Ëä\ﬂB¨\0'),('.Str:\Ëä\ﬂB¨\0'),('.Stä:\Ëä\ﬂB¨\0'),('.Stü:\Ëä\ﬂB¨\0');
/*!40000 ALTER TABLE `brokenutf8alter` ENABLE KEYS */;
UNLOCK TABLES;
/*!50112 SET @disable_bulk_load = IF (@is_rocksdb_supported, 'SET SESSION rocksdb_bulk_load = @old_rocksdb_bulk_load', 'SET @dummy_rocksdb_bulk_load = 0') */;
/*!50112 PREPARE s FROM @disable_bulk_load */;
/*!50112 EXECUTE s */;
/*!50112 DEALLOCATE PREPARE s */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2018-04-07  3:48:50
