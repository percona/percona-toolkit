use test;

-- This table is designed not to work right with ascending slices unless
-- mk-archiver gets the ascending slice right.  The important thing is that
-- the PK columns aren't in the same order as the columns.  If mk-archiver
-- ascends by the first two columns 2 rows at a time, confusing column ordinals
-- with PK ordinals, some rows won't get archived.
drop table if exists table_11;
CREATE TABLE table_11 (
   pk_2 int not null,
   col_1 int not null,
   pk_1 int not null,
   primary key(pk_1, pk_2)
);
-- Notice how the values are being inserted in PK order, but out of
-- first-two-columns-scan order:
insert into table_11(pk_2, col_1, pk_1)
   values
   (1, 1, 1),
   (2, 3, 1),
   (1, 0, 2),
   (1, 0, 3);

