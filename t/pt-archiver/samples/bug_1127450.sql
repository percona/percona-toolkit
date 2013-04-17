DROP DATABASE IF EXISTS `bug_1127450`;
CREATE DATABASE `bug_1127450`;
CREATE TABLE `bug_1127450`.`original` (
   id int,
   t text CHARACTER SET utf8,
   PRIMARY KEY(id)
) engine=InnoDB DEFAULT CHARSET=utf8;
CREATE TABLE `bug_1127450`.`copy` (
   id int,
   t text CHARACTER SET utf8,
   PRIMARY KEY(id)
) engine=InnoDB DEFAULT CHARSET=utf8;
