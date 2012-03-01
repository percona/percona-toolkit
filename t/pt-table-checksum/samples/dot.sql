drop database if exists test;
create database test;
use test;

CREATE TABLE t (
  `No.` varchar(16) NOT NULL DEFAULT '',
  `foo.bar` varchar(16),
  PRIMARY KEY (`No.`)
) ENGINE=MyISAM;

insert into t values
  ('one', 'a'),
  ('two', 'a'),
  ('three', 'a'),
  ('four', 'a'),
  ('five', 'a'),
  ('six', 'a'),
  ('seven', 'a'),
  ('eight', 'a'),
  ('nine', 'a'),
  ('ten', 'a');
