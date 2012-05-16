drop database if exists test;
create database test;
use test;

CREATE TABLE t (
  `ufi` int(11) NOT NULL,
  `guest_language` char(2) NOT NULL,
  `guest_country` char(2) NOT NULL,
  `score` int(10) unsigned NOT NULL,
  PRIMARY KEY (`ufi`,`guest_language`,`guest_country`),
  KEY `guest_language` (`guest_language`,`guest_country`,`score`)
) ENGINE=InnoDB;

INSERT INTO t VALUES
  (1, 'en', 'en', 1),
  (2, 'fr', 'fr', 1),
  (3, 'es', 'es', 1),
  (4, 'ru', 'ru', 1),
  (5, 'sl', 'sl', 1),
  (6, 'ch', 'ch', 1),
  (7, 'en', 'en', 1),
  (8, 'fr', 'fr', 1),
  (9, 'es', 'es', 1),
  (10,'ru', 'ru', 1),
  (11,'sl', 'sl', 1),
  (12,'aa', 'ch', 1),
  (10,'ab', 'ru', 1),
  (11,'ac', 'sl', 1),
  (12,'ad', 'ch', 1);
