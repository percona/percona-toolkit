drop database if exists bri;
create database bri;
use bri;
create table t (
   id int unsigned NOT NULL auto_increment primary key,
   c  char(16),
   t  time
) engine=innodb;

create table t_arch (
   id int unsigned NOT NULL auto_increment primary key,
   c  char(16),
   t  time
) engine=innodb;

insert into t values
   (null, 'aa', '11:11:11'),
   (null, 'bb', '11:11:12'),
   (null, 'cc', '11:11:13'),
   (null, 'dd', '11:11:14'),
   (null, 'ee', '11:11:15'),
   (null, 'ff', '11:11:16'),
   (null, 'gg', '11:11:17'),
   (null, 'hh', '11:11:18'),
   (null, 'ii', '11:11:19'),
   (null, 'jj', '11:11:10');
