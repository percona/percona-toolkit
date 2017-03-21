DROP DATABASE IF EXISTS my_binary_database; 
CREATE DATABASE my_binary_database CHARSET=binary;
USE my_binary_database;

CREATE TABLE `sentinel` (
  `id` int(11) NOT NULL,
  `ping` varchar(64) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

INSERT INTO sentinel VALUES(1, '231f9da77ba0bf7e517b790334433cd3');
