DROP DATABASE IF EXISTS test;
CREATE DATABASE test;

USE test;
create table t1(
    id int not null auto_increment primary key, 
    f1 varchar(10)
);
insert into t1(f1) values('😜');
insert into t1(f1) select f1 from t1;
insert into t1(f1) select f1 from t1;
insert into t1(f1) select f1 from t1;
