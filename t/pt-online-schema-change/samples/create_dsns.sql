CREATE DATABASE IF NOT EXISTS test_recursion_method;
USE test_recursion_method;
DROP TABLE IF EXISTS `dsns`;
CREATE TABLE `dsns` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `parent_id` int(11) DEFAULT NULL,
  `dsn` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;

INSERT INTO `dsns` VALUES (1, 12345, "D=test_recursion_method,t=dsns,P=12346,h=127.0.0.1,u=root,p=msandbox");
INSERT INTO `dsns` VALUES (2, 12345, "D=test_recursion_method,t=dsns,P=12347,h=127.0.0.1,u=root,p=msandbox");

