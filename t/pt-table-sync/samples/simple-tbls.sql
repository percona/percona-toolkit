DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

-- InnoDB table 1
CREATE TABLE it1 (
  id int not null auto_increment primary key,
  a int not null,
  b int not null,
  c varchar(16) not null,
  key (a),
  unique key (c),
  unique key (id, c)
) ENGINE=InnoDB;

-- InnoDB table 2
CREATE TABLE it2 LIKE it1;

-- Empty InnoDB table
CREATE TABLE empty_it LIKE it1;

-- MyISAM table 1
CREATE TABLE mt1 (
  id int not null auto_increment primary key,
  a int not null,
  b int not null,
  c varchar(16) not null,
  key (a),
  unique key (c),
  unique key (id, c)
) ENGINE=MyISAM;

-- MyISAM table 2
CREATE TABLE mt2 LIKE mt1;

-- Empty MyISAM table
CREATE TABLE empty_mt LIKE mt1;

INSERT INTO it1 VALUES
  (null, 1, 1, 'one'),
  (null, 2, 2, 'two'),
  (null, 3, 3, 'three'), 
  (null, 4, 4, 'four'),
  (null, 5, 5, 'file'),
  (null, 6, 6, 'six'), 
  (null, 7, 7, 'seven'),
  (null, 8, 8, 'eight'),
  (null, 9, 9, 'nine'), 
  (null,10,10, 'ten');

INSERT INTO mt1 VALUES
  (null, 1, 1, 'one'),
  (null, 2, 2, 'two'),
  (null, 3, 3, 'three'), 
  (null, 4, 4, 'four'),
  (null, 5, 5, 'file'),
  (null, 6, 6, 'six'), 
  (null, 7, 7, 'seven'),
  (null, 8, 8, 'eight'),
  (null, 9, 9, 'nine'), 
  (null,10,10, 'ten');

