SET NAMES utf8mb4;
DROP DATABASE IF EXISTS pt_2123;
CREATE DATABASE pt_2123;

CREATE TABLE `pt_2123`.`t1` (
	`col1` int(11) NOT NULL AUTO_INCREMENT,
	`col2` varchar(3) DEFAULT NULL,
	PRIMARY KEY (`col1`) 
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4;

CREATE TABLE `pt_2123`.`t2` (
	`col1` int(11) NOT NULL AUTO_INCREMENT,
	`col2` varchar(3) DEFAULT NULL,
	PRIMARY KEY (`col1`) 
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4;

insert into pt_2123.t1 (col2) values ('あ');
insert into pt_2123.t1 (col2) values ('あ');
insert into pt_2123.t1 (col2) values ('あ');
insert into pt_2123.t1 (col2) values ('あ');
insert into pt_2123.t1 (col2) values ('w');
