use test;

-- This table and table_8/9 designed to check that ON DUPLICATE KEY UPDATE can
-- work okay with the before_insert functionality.

drop table if exists table_7;
create table table_7(
   a int not null,
   b int not null,
   c int not null,
   primary key(a, b)
) engine=innodb;

drop table if exists table_8;
create table table_8 like table_7;

drop table if exists table_9;
create table table_9(
   a int not null primary key,
   b int not null,
   c int not null
) engine=innodb;

insert into table_7(a, b, c) values
   (1, 2, 1),
   (1, 3, 5);

