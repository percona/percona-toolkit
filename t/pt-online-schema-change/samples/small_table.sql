DROP DATABASE IF EXISTS `mkosc`;
CREATE DATABASE `mkosc`;
USE `mkosc`;
CREATE TABLE a (
  i int auto_increment primary key,
  c char(16),
  d date
) ENGINE=MyISAM;
INSERT INTO a VALUES
   (null, 'a', now()),
   (null, 'b', now()),
   (null, 'c', now()),
   (null, 'd', now()),
   (null, 'e', now()),
   (null, 'f', now()),
   (null, 'g', now()),
   (null, 'h', now()),
   (null, 'i', now()),
   (null, 'j', now()),
   (null, 'k', now()),
   (null, 'l', now()),
   (null, 'm', now()),
   (null, 'n', now()),
   (null, 'o', now()),
   (null, 'p', now()),
   (null, 'q', now()),
   (null, 'r', now());
