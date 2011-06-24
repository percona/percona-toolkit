use test;

drop table if exists table_6;
create table table_6(
   a int not null,
   b int not null,
   c int,
   primary key(a, b)
);

-- This test data specifically designed to be ambiguous unless the
-- ascending-index WHERE clause is carefully wrapped in parens.  If the archiver
-- goes to 2 rows and doesn't wrap right, it will archive the 3rd row which it
-- should not because it archives c=1.
insert into table_6(a, b, c)
   values(1, 1, 1), (1, 2, 1), (1, 3, 0);

