CREATE DATABASE IF NOT EXISTS test_ssl;
USE test_ssl;
DROP TABLE IF EXISTS `dsns`;
CREATE TABLE `dsns` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `parent_id` int(11) DEFAULT NULL,
  `dsn` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;

INSERT INTO `dsns` VALUES (1, NULL, "F=t/pt-archiver/samples/pt-191-replica1.cnf,P=12346,h=127.0.0.1,u=root,p=msandbox,s=1");
INSERT INTO `dsns` VALUES (2, NULL, "F=t/pt-archiver/samples/pt-191-replica2.cnf,P=12347,h=127.0.0.1,u=root,p=msandbox,s=1");

