use test;

drop table if exists table_1;
drop table if exists table_2;
drop table if exists table_3;
drop table if exists table_4;

drop table if exists stat_test;
create table stat_test(a int);

create table table_1(
   a int not null primary key,
   b int,
   c int not null,
   d varchar(50),
   key(b)
) engine=innodb;

create table table_2(
   a int not null primary key auto_increment,
   b int,
   c int not null,
   d varchar(50)
) engine=innodb;

create table table_3(
   a int not null,
   b int,
   c int not null,
   d varchar(50),
   primary key(a, c)
) engine=innodb;

create table table_4(
   a int
) engine=innodb;

insert into table_1 values
   (1, 2,    3, 4),
   (2, null, 3, 4),
   (3, 2,    3, "\t"),
   (4, 2,    3, "\n");

insert into table_3 select * from table_1;
