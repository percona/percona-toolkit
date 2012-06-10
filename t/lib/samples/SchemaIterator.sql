--
-- d1
--
DROP DATABASE IF EXISTS d1;
CREATE DATABASE d1;

CREATE TABLE d1.t1 (
  id int auto_increment primary key,
  c  char(8)
) ENGINE=MyISAM CHARSET=utf8;

CREATE TABLE d1.t2 (
  id int auto_increment primary key,
  c  varchar(8)
) ENGINE=InnoDB;

CREATE TABLE d1.t3 (
  id int auto_increment primary key,
  c  char(8)
) ENGINE=MEMORY;

INSERT INTO d1.t1 VALUES (null, 'a'), (null, 'b'), (null, 'c'), (null, 'd'), (null, 'e'), (null, 'f'), (null, 'g'), (null, 'h'), (null, 'i');
INSERT INTO d1.t2 SELECT * FROM d1.t1;
INSERT INTO d1.t3 SELECT * FROM d1.t1;

--
-- d2
--
DROP DATABASE IF EXISTS d2;
CREATE DATABASE d2;

CREATE TABLE d2.t1 (
  id int auto_increment primary key,
  c  char(8)
);
-- d2.t1 is an empty table.

--
-- d3
--
DROP DATABASE IF EXISTS d3;
CREATE DATABASE d3;
-- d3 is an empty database.
