use test;
create table L (
  l_id int not null primary key
);
insert into L(l_id) values(1),(2),(3);

create table R (
  r_id int not null primary key,
  r_other int NULL -- notice that this is NULL-able
);
insert into R(r_id, r_other) values(1, 5), (2, NULL);
