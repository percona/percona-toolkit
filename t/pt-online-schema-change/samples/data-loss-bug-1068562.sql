drop database if exists bug1068562;
create database bug1068562;
use bug1068562;

CREATE TABLE `simon` (
  `id` int(11) NOT NULL,
  `old_column_name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

insert into simon values (1,'a'),(2,'b'),(3,'c');
