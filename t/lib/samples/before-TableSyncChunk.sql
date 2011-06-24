use test;

drop table if exists test1,test2,test3,test4,test5,test6;

create table test1(
   a int not null,
   b char(2) not null,
   primary key(a, b),
   unique key (a)
) ENGINE=INNODB;

create table test2(
   a int not null,
   b char(2) not null,
   primary key(a, b),
   unique key (a)
) ENGINE=INNODB;

insert into test1 values(1, 'en'), (2, 'ca'), (3, 'ab'), (4, 'bz');

create table test3(a int not null primary key, b int not null, unique(b));
create table test4(a int not null primary key, b int not null, unique(b));
insert into test3 values(1, 2), (2, 1);
insert into test4 values(1, 1), (2, 2);
create table test5(a varchar(5));
create table test6(a varchar(16), unique index (a));
