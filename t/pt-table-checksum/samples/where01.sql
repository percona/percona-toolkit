drop database if exists test;
create database test;
use test;

CREATE TABLE `checksum_test` (
  `id` int(11) NOT NULL DEFAULT '0',
  `date` date DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

INSERT INTO `checksum_test` VALUES 
      (1, '2011-03-01'), 
      (2, '2011-03-01'), 
      (3, '2011-03-01'), 
      (4, '2011-03-01'), 
      (5, '2011-03-01'), 
      (6, '2011-03-02'), 
      (7, '2011-03-02'), 
      (8, '2011-03-02'), 
      (9, '2011-03-02'), 
      (10, '2011-03-02'), 
      (11, '2011-03-03'), 
      (12, '2011-03-03'), 
      (13, '2011-03-03'), 
      (14, '2011-03-03'), 
      (15, '2011-03-03');
