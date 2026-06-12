DROP DATABASE IF EXISTS qrf;
CREATE DATABASE qrf;
USE qrf;
CREATE TABLE t (
   i int not null auto_increment primary key,
   v varchar(16)
) engine=InnoDB;
insert into qrf.t values
   (1, 'hello'),
   (2, ','),
   (3, 'world'),
   (4, '!');
