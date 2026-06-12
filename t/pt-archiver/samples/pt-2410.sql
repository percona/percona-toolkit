CREATE DATABASE pt_2410;
USE pt_2410;

CREATE TABLE test(
    id int not null primary key auto_increment,
    column1 int default null,
    column2 varchar(50) not null);

INSERT INTO test VALUES (null,null,'testing...');
INSERT INTO test VALUES (null,null,'testing...');
