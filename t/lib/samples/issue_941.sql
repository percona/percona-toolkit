drop database if exists issue_941;
create database issue_941;
use issue_941;

create table i (
   i int not null,
   unique key (i)
);
insert into i values (0),(100),(101),(102),(103),(104),(105),(106),(107);

create table i_neg (
   i_neg int not null,
   unique key (i_neg)
);
insert into i_neg values (-10),(-9),(-8),(-7),(-6),(-5),(-4),(-2);

create table i_neg_pos (
   i_neg_pos int not null,
   unique key (i_neg_pos)
);
insert into i_neg_pos values (-10),(-9),(-8),(-7),(-6),(-5),(-4),(-2),(-1),(0),(1),(2),(3),(4);

create table i_null (
   i_null int,
   unique key (i_null)
);
insert into i_null values (null),(100),(101),(102),(103),(104),(105),(106),(107);

create table d (
   d  date not null,
   unique key (d)
);
insert into d values
   ('0000-00-00'),
   ('2010-03-01'),
   ('2010-03-02'),
   ('2010-03-03'),
   ('2010-03-04'),
   ('2010-03-05');

create table dt (
   dt  datetime not null,
   unique key (dt)
);
insert into dt values
   ('0000-00-00 00:00:00'),
   ('2010-03-01 02:01:00'),
   ('2010-03-01 10:06:00'),
   ('2010-03-03 11:03:00'),
   ('2010-03-03 05:00:00'),
   ('2010-03-05 00:30:00');
