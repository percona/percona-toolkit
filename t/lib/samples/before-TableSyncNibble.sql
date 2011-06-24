use test;

drop table if exists test1,test2,test3,test4;

create table test1(
   a int not null,
   b char(2) not null,
   c char(2) not null,
   primary key(a, b)
) ENGINE=INNODB;

create table test2(
   a int not null,
   b char(2) not null,
   c char(2) not null,
   primary key(a, b)
) ENGINE=INNODB;

insert into test1 values(1, 'en', 'a'), (2, 'ca', 'b'), (3, 'ab', 'c'),
   (4, 'bz', 'd');
