drop database if exists bug_1315130_a;
create database bug_1315130_a;
use bug_1315130_a;
create table parent_table (a int unsigned primary key);
create table child_table_in_same_schema (a int unsigned primary key, constraint a_fk foreign key a_fk (a) references parent_table(a));
drop database if exists bug_1315130_b;
create database bug_1315130_b;
use bug_1315130_b;
create table child_table_in_second_schema (a int unsigned primary key, constraint a_fk foreign key a_fk (a) references bug_1315130_a.parent_table(a));
create table parent_table (a int unsigned primary key);
create table bug_1315130_a.child_table_in_same_schema_referencing_second_schema (a int unsigned primary key, constraint a_fk2 foreign key a_fk2 (a) references bug_1315130_b.parent_table(a));

