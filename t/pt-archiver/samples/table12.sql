use test;

-- This test uses an auto_increment colum to test --safeautoinc.
drop table if exists table_12;
create table table_12( a int not null auto_increment primary key, b int) engine=innodb;
insert into table_12(a,b) values(1,1),(2,1),(3,1);

