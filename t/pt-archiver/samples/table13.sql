use test;

-- This test moves rows to different tables depending on the value of a
-- column.
drop table if exists table_13, table_odd, table_even;
create table table_13(a int not null primary key);
insert into table_13(a) values(1),(2),(3);
