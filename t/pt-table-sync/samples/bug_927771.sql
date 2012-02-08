drop database if exists test;
create database test;
use test;
create table t (
  id int auto_increment not null primary key,
  c  varchar(8) not null
) engine=innodb;
insert into test.t values
  (null, 'a'),
  (null, 'b'),
  (null, 'c'),
  (null, 'd'),
  (null, 'e'),
  (null, 'f'),
  (null, 'g'),
  (null, 'h'),
  (null, 'i'),
  (null, 'j');
