drop database if exists issue_519;
create database issue_519;
use issue_519;
create table t (
   i int unsigned not null auto_increment primary key,
   y year not null,
   t text,
   unique index (y),
   index `myidx` (i, y)
);
insert into t values
   (null,'2000','a'),
   (null,'2001','b'),
   (null,'2002','c'),
   (null,'2003','d'),
   (null,'2004','e'),
   (null,'2005','f'),
   (null,'2006','g'),
   (null,'2007','h'),
   (null,'2008','i'),
   (null,'2009','j'),
   (null,'2010','k');

