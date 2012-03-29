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
   (null, 'a', now()),
   (null, 'b', now()),
   (null, 'c', now()),
   (null, 'd', now()),
   (null, 'e', now()),
   (null, 'f', now()),
   (null, 'g', now()),
   (null, 'h', now()),
   (null, 'i', now()),
   (null, 'j', now()), -- 10
   (null, 'k', now()),
   (null, 'l', now()),
   (null, 'm', now()),
   (null, 'n', now()),
   (null, 'o', now()),
   (null, 'p', now()),
   (null, 'q', now()),
   (null, 'r', now()),
   (null, 's', now()),
   (null, 't', now()); -- 20
