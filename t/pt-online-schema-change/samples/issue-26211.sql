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


DROP DATABASE IF EXISTS `bug_26211`;
CREATE DATABASE `bug_26211`;
USE `bug_26211`;

DROP TABLE IF EXISTS `mref`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `mref` (
  `M_ID` decimal(10,0) NOT NULL ,
  `PR_M_INST_ID` decimal(10,0) NOT NULL ,
  KEY `I_M_ID` (`M_ID`),
  KEY `I_PR_M_` (`PR_M_INST_ID`),
  CONSTRAINT `FK_MREF_REF_PM` FOREIGN KEY (`M_ID`) REFERENCES `pm` (`M_ID`) ON DELETE CASCADE,
  CONSTRAINT `FK_MREF_REF_PRMI` FOREIGN KEY (`PR_M_INST_ID`) REFERENCES `prm_inst` (`PR_M_INST_ID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

DROP TABLE IF EXISTS `pm`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `pm` (
  `M_ID` decimal(10,0) NOT NULL ,
  `P_MR_NUM` varchar(64) NOT NULL ,
  `P_NUM` varchar(50) NOT NULL ,
  `TYPE` varchar(50) DEFAULT NULL ,
  `VERSION` decimal(10,0) NOT NULL ,
  `XML` longtext NOT NULL ,
  PRIMARY KEY (`M_ID`),
  UNIQUE KEY `UK_PM` (`P_MR_NUM`,`P_NUM`),
  KEY `I_PM_P_NUM` (`P_NUM`),
  CONSTRAINT `FK_PM_REF_P` FOREIGN KEY (`P_NUM`) REFERENCES `p` (`P_NUM`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

DROP TABLE IF EXISTS `p`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `p` (
  `P_NUM` varchar(50) NOT NULL ,
  `VERSION` decimal(10,0) NOT NULL ,
  `TYPE` varchar(32) NOT NULL ,
  `PROTECTED` decimal(1,0) NOT NULL ,
  `DESCRIPTIONS` varchar(4000) DEFAULT NULL ,
  PRIMARY KEY (`P_NUM`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;


DROP TABLE IF EXISTS `pr`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `pr` (
  `PR_ID` decimal(10,0) NOT NULL ,
  `NUM` varchar(64) NOT NULL ,
  `HUB_RQD` decimal(1,0) NOT NULL ,
  `TP_RQD` decimal(1,0) NOT NULL ,
  `TRANS_TYPE_RQD` decimal(1,0) NOT NULL ,
  `HUB_LABEL` varchar(255) DEFAULT NULL ,
  `TP_LABEL` varchar(255) DEFAULT NULL ,
  `TRANS_TYPE_LABEL` varchar(255) DEFAULT NULL ,
  `TYPE` varchar(32) NOT NULL ,
  `PR_M_FLAG` decimal(1,0) NOT NULL ,
  `USER_DEFINED` decimal(1,0) NOT NULL ,
  `DESCRIPTIONS` varchar(4000) DEFAULT NULL ,
  `SIGNATURE` longtext ,
  PRIMARY KEY (`PR_ID`),
  KEY `pr_num_index` (`NUM`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

DROP TABLE IF EXISTS `prm`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `prm` (
  `PR_M_ID` decimal(10,0) NOT NULL ,
  `M_ID` decimal(10,0) NOT NULL ,
  `PR_ID` decimal(10,0) DEFAULT NULL ,
  `ACTIVE_VERSION` decimal(10,0) DEFAULT NULL ,
  `CURRENT_VERSION` decimal(10,0) DEFAULT NULL ,
  `ENABLED` decimal(1,0) NOT NULL ,
  `NUM` varchar(64) NOT NULL ,
  PRIMARY KEY (`PR_M_ID`),
  KEY `I_PRM_M_ID` (`M_ID`),
  KEY `I_PRM_PR_ID` (`PR_ID`),
  KEY `prm_num_indx` (`NUM`),
  CONSTRAINT `FK_PMOD_REF_PR` FOREIGN KEY (`PR_ID`) REFERENCES `pr` (`PR_ID`),
  CONSTRAINT `FK_PRM_REF_PM` FOREIGN KEY (`M_ID`) REFERENCES `pm` (`M_ID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

DROP TABLE IF EXISTS `prm_inst`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `prm_inst` (
  `PR_M_INST_ID` decimal(10,0) NOT NULL,
  `VERSION` decimal(10,0) NOT NULL,
  `PR_M_ID` decimal(10,0) NOT NULL,
  PRIMARY KEY (`PR_M_INST_ID`),
  UNIQUE KEY `UK_PRM_INST` (`VERSION`,`PR_M_ID`),
  KEY `I_PRM_INST_PR_MODE` (`PR_M_ID`),
  CONSTRAINT `FK_PRMI_REF_PRM` FOREIGN KEY (`PR_M_ID`) REFERENCES `prm` (`PR_M_ID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;



