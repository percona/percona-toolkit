use test;
create table resume (
   i int not null unique key
) engine=innodb;
insert into test.resume values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10);
