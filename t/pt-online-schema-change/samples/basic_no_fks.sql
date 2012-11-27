DROP DATABASE IF EXISTS pt_osc;
CREATE DATABASE pt_osc;
USE pt_osc;
CREATE TABLE t (
  id int auto_increment primary key,
  c  char(32),
  d  date,
  unique index (c(32))
) ENGINE=MyISAM;
INSERT INTO pt_osc.t VALUES
   (1, 'a', now()),
   (2, 'b', now()),
   (3, 'c', now()),
   (4, 'd', now()),
   (5, 'e', now()),
   (6, 'f', now()),
   (7, 'g', now()),
   (8, 'h', now()),
   (9, 'i', now()),
   (10, 'j', now()), -- 10
   (11, 'k', now()),
   (12, 'l', now()),
   (13, 'm', now()),
   (14, 'n', now()),
   (15, 'o', now()),
   (16, 'p', now()),
   (17, 'q', now()),
   (18, 'r', now()),
   (19, 's', now()),
   (20, 't', now()); -- 20
