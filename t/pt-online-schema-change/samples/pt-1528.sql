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
INSERT INTO `brokenutf8alter` VALUES ('.SG�:\�\�B�\0'),('.SK,:\�\�B�\0'),('.SL_:\�\�B�\0'),('.SL\�:\�\�B�\0'),('.SMB:\�\�B�\0'),('.SM�:\�\�B�\0'),('.SM�:\�\�B�\0'),('.SOE:\�\�B�\0'),('.SO�:\�\�B�\0'),('.SP:\�\�B�\0'),('.SPZ:\�\�B�\0'),('.SP�:\�\�B�\0'),('.SQ:\�\�B�\0'),('.SQX:\�\�B�\0'),('.SQ�:\�\�B�\0'),('.SQ�:\�\�B�\0'),('.SRK:\�\�B�\0'),('.ST4:\�\�B�\0'),('.SU=:\�\�B�\0'),('.SU�:\�\�B�\0'),('.SU�:\�\�B�\0'),('.SVC:\�\�B�\0'),('.SV�:\�\�B�\0'),('.SV\�:\�\�B�\0'),('.SW8:\�\�B�\0'),('.SW�:\�\�B�\0'),('.SX\�:\�\�B�\0'),('.SY\":\�\�B�\0'),('.SYr:\�\�B�\0'),('.SY\�:\�\�B�\0'),('.SZ:\�\�B�\0'),('.SZ�:\�\�B�\0'),('.S[):\�\�B�\0'),('.S[�:\�\�B�\0'),('.S\\N:\�\�B�\0'),('.S\\\�:\�\�B�\0'),('.S]>:\�\�B�\0'),('.S]�:\�\�B�\0'),('.S]\�:\�\�B�\0'),('.S^.:\�\�B�\0'),('.S^:\�\�B�\0'),('.S^\�:\�\�B�\0'),('.S_8:\�\�B�\0'),('.S_�:\�\�B�\0'),('.S`W:\�\�B�\0'),('.S`�:\�\�B�\0'),('.Sa~:\�\�B�\0'),('.Sb:\�\�B�\0'),('.Sb�:\�\�B�\0'),('.Sc>:\�\�B�\0'),('.Sc\�:\�\�B�\0'),('.Sd:\�\�B�\0'),('.Sdv:\�\�B�\0'),('.Sd\�:\�\�B�\0'),('.Se:\�\�B�\0'),('.Seb:\�\�B�\0'),('.Se�:\�\�B�\0'),('.Sf:\�\�B�\0'),('.SfP:\�\�B�\0'),('.Sf�:\�\�B�\0'),('.Sf�:\�\�B�\0'),('.Sg?:\�\�B�\0'),('.Sg�:\�\�B�\0'),('.Sh:\�\�B�\0'),('.Sh�:\�\�B�\0'),('.Si7:\�\�B�\0'),('.Si\�:\�\�B�\0'),('.Sji:\�\�B�\0'),('.Sk:\�\�B�\0'),('.Sk�:\�\�B�\0'),('.Sk\�:\�\�B�\0'),('.Sl(:\�\�B�\0'),('.Sl{:\�\�B�\0'),('.Sl\�:\�\�B�\0'),('.Sm\Z:\�\�B�\0'),('.Smh:\�\�B�\0'),('.Sm�:\�\�B�\0'),('.Sn:\�\�B�\0'),('.So:\�\�B�\0'),('.Sob:\�\�B�\0'),('.So�:\�\�B�\0'),('.Sp:\�\�B�\0'),('.SpQ:\�\�B�\0'),('.Sp�:\�\�B�\0'),('.Sp�:\�\�B�\0'),('.SqA:\�\�B�\0'),('.Sq�:\�\�B�\0'),('.Sq\�:\�\�B�\0'),('.Sr+:\�\�B�\0'),('.Srv:\�\�B�\0'),('.Sr�:\�\�B�\0'),('.Ss:\�\�B�\0'),('.Ss_:\�\�B�\0'),('.St:\�\�B�\0'),('.St :\�\�B�\0'),('.St5:\�\�B�\0'),('.StI:\�\�B�\0'),('.St^:\�\�B�\0'),('.Str:\�\�B�\0'),('.St�:\�\�B�\0'),('.St�:\�\�B�\0');
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
