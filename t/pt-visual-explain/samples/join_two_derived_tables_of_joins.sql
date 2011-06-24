explain
select * from (
   select 1 as foo from sakila.actor as actor_1
   cross join sakila.actor as actor_2
) as x
inner join (
   select 1 as foo from sakila.actor as actor_3
   cross join sakila.actor as actor_4
) as y using (foo);
+----+-------------+------------+-------+---------------+---------+---------+------+-------+-------------+
| id | select_type | table      | type  | possible_keys | key     | key_len | ref  | rows  | Extra       |
+----+-------------+------------+-------+---------------+---------+---------+------+-------+-------------+
|  1 | PRIMARY     | <derived2> | ALL   | NULL          | NULL    | NULL    | NULL | 40000 |             | 
|  1 | PRIMARY     | <derived3> | ALL   | NULL          | NULL    | NULL    | NULL | 40000 | Using where | 
|  3 | DERIVED     | actor_3    | index | NULL          | PRIMARY | 2       | NULL |   200 | Using index | 
|  3 | DERIVED     | actor_4    | index | NULL          | PRIMARY | 2       | NULL |   200 | Using index | 
|  2 | DERIVED     | actor_1    | index | NULL          | PRIMARY | 2       | NULL |   200 | Using index | 
|  2 | DERIVED     | actor_2    | index | NULL          | PRIMARY | 2       | NULL |   200 | Using index | 
+----+-------------+------------+-------+---------------+---------+---------+------+-------+-------------+
