use test;
drop table if exists table_1;

create table table_1(
   a int not null primary key,
   b int,
   c int not null,
   d varchar(50),
   key(b)
) engine=innodb;

insert into table_1 values
   (1, 2,    3, 4),
   (2, null, 3, 4),
   (3, 2,    3, "\t"),
   (4, 2,    3, "\n");
