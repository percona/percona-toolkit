create database if not exists test;
use test;

drop table if exists test1;
drop table if exists test2;

create table test1(
   a int not null,
   b char(2) not null,
   primary key(a, b)
) ENGINE=INNODB;

create table test2(
   a int not null,
   b char(2) not null,
   primary key(a, b)
) ENGINE=INNODB;

insert into test1 values(1, 'en'), (2, 'ca');

drop table if exists test3, test4;
create table test3 (
  id int not null primary key,
  name varchar(255)
);
create table test4 (
  id int not null primary key,
  name varchar(255)
);
insert into test3(id, name) values(15034, '51707'),(1, '001');
insert into test4(id, name) values(15034, '051707'),(1, '1');
