DROP DATABASE IF EXISTS qrf;
CREATE DATABASE qrf;
USE qrf;
CREATE TABLE t (
   i int not null auto_increment primary key,
   v varchar(16)
) engine=InnoDB;
insert into qrf.t values
   (null, 'hello'),
   (null, ','),
   (null, 'world'),
   (null, '!');
