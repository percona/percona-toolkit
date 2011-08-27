drop database if exists test;
create database test;
use test;

CREATE TABLE `checksum_test` (
  `id` varchar(255) NOT NULL,
  `date` date DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

INSERT INTO `checksum_test` VALUES 
      ('Apple',       '2011-03-03'), 
      ('banana',      '2011-03-01'), 
      ('orange',      '2011-03-01'), 
      ('grape',       '2011-03-01'), 
      ('kiwi',        '2011-03-01'), 
      ('strawberry',  '2011-03-02'), 
      ('peach',       '2011-03-02'), 
      ('mango',       '2011-03-02'), 
      ('tomato',      '2011-03-02'), 
      ('nectarine',   '2011-03-02'), 
      ('pear',        '2011-03-01'), 
      ('lemon',       '2011-03-03'), 
      ('lime',        '2011-03-03'), 
      ('pineapple',   '2011-03-03'), 
      ('raspberry',   '2011-03-03');
