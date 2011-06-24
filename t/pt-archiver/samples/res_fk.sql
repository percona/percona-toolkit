DROP DATABASE IF EXISTS test;
DROP DATABASE IF EXISTS test_archived;
CREATE DATABASE test;
CREATE DATABASE test_archived;
USE test;

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
-- Table structure for table `comp`
--

DROP TABLE IF EXISTS `comp`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `comp` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `name` varchar(255) default NULL,
  `otherinfo` varchar(255) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `comp`
--

LOCK TABLES `comp` WRITE;
/*!40000 ALTER TABLE `comp` DISABLE KEYS */;
INSERT INTO `comp` VALUES (1,'Company1','best customer'),(2,'Company2','worst customer'),(3,'Company3','average joe');
/*!40000 ALTER TABLE `comp` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `prod`
--

DROP TABLE IF EXISTS `prod`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `prod` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `comp_id` int(10) unsigned default '0',
  `prod_name` varchar(255) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `prod_comp_id` (`comp_id`),
  CONSTRAINT `prod_comp_id` FOREIGN KEY (`comp_id`) REFERENCES `comp` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `prod`
--

LOCK TABLES `prod` WRITE;
/*!40000 ALTER TABLE `prod` DISABLE KEYS */;
INSERT INTO `prod` VALUES (1,1,'hairspay'),(2,1,'gel'),(3,2,'lumber'),(4,2,'concrete'),(5,3,'wiigame'),(6,3,'ps3game');
/*!40000 ALTER TABLE `prod` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `prod_details`
--

DROP TABLE IF EXISTS `prod_details`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `prod_details` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `prod_id` int(10) unsigned NOT NULL default '0',
  `detail` varchar(255) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `prod_det_prod_id` (`prod_id`),
  CONSTRAINT `prod_det_prod_id` FOREIGN KEY (`prod_id`) REFERENCES `prod` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `prod_details`
--

LOCK TABLES `prod_details` WRITE;
/*!40000 ALTER TABLE `prod_details` DISABLE KEYS */;
INSERT INTO `prod_details` VALUES (1,1,'something'),(2,2,'something else'),(3,3,'totally different'),(4,4,'I\'m out of ideas'),(5,5,'better find out something'),(6,6,'finally last one');
/*!40000 ALTER TABLE `prod_details` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user`
--

DROP TABLE IF EXISTS `user`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `user` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `comp_id` int(10) unsigned NOT NULL default '0',
  `prod_id` int(10) unsigned NOT NULL default '0',
  `name` varchar(255) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `user_comp_id` (`comp_id`),
  KEY `user_prod_id` (`prod_id`),
  CONSTRAINT `user_comp_id` FOREIGN KEY (`comp_id`) REFERENCES `comp` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_prod_id` FOREIGN KEY (`prod_id`) REFERENCES `prod` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Dumping data for table `user`
--

LOCK TABLES `user` WRITE;
/*!40000 ALTER TABLE `user` DISABLE KEYS */;
INSERT INTO `user` VALUES (1,1,1,'robert'),(2,1,2,'robert'),(3,2,3,'gert-jan'),(4,3,6,'olle');
/*!40000 ALTER TABLE `user` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- CREATE TABLE LIKE doesn't do foreign keys.
USE test_archived;
CREATE TABLE `comp` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `name` varchar(255) default NULL,
  `otherinfo` varchar(255) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB;
CREATE TABLE `prod` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `comp_id` int(10) unsigned default '0',
  `prod_name` varchar(255) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `prod_comp_id` (`comp_id`),
  CONSTRAINT `prod_comp_id` FOREIGN KEY (`comp_id`) REFERENCES `comp` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;
CREATE TABLE `prod_details` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `prod_id` int(10) unsigned NOT NULL default '0',
  `detail` varchar(255) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `prod_det_prod_id` (`prod_id`),
  CONSTRAINT `prod_det_prod_id` FOREIGN KEY (`prod_id`) REFERENCES `prod` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;
CREATE TABLE `user` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `comp_id` int(10) unsigned NOT NULL default '0',
  `prod_id` int(10) unsigned NOT NULL default '0',
  `name` varchar(255) NOT NULL default '0',
  PRIMARY KEY  (`id`),
  KEY `user_comp_id` (`comp_id`),
  KEY `user_prod_id` (`prod_id`),
  CONSTRAINT `user_comp_id` FOREIGN KEY (`comp_id`) REFERENCES `comp` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `user_prod_id` FOREIGN KEY (`prod_id`) REFERENCES `prod` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB;

-- Dump completed on 2009-10-12  8:52:04
