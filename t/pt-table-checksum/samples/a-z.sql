drop database if exists test;
create database test;
use test;

create table t (
  id  int auto_increment primary key,
  c   varchar(16) not null
) engine=innodb;

insert into t values (null, 'a'),(null, 'b'),(null, 'c'),(null, 'd'),(null, 'e'),(null, 'f'),(null, 'g'),(null, 'h'),(null, 'i'),(null, 'j'),(null, 'k'),(null, 'l'),(null, 'm'),(null, 'n'),(null, 'o'),(null, 'p'),(null, 'q'),(null, 'r'),(null, 's'),(null, 't'),(null, 'u'),(null, 'v'),(null, 'w'),(null, 'x'),(null, 'y'),(null, 'z');
