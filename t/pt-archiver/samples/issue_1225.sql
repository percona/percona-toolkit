set names 'utf8';
drop database if exists issue_1225;
create database issue_1225;
use issue_1225;
create table t (
   i int not null auto_increment primary key,
   c char(16)
) charset=utf8;
create table a (
   i int not null primary key,
   c char(16)
) charset=utf8;
insert into t values
   (null, "が"),
   (null, "が"),
   (null, "が");
