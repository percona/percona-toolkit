explain
select * from (
   select 1 as foo
   from sakila.actor as actor_1,
      sakila.actor as actor_2
) as x;
+----+-------------+------------+-------+---------------+---------+---------+------+-------+-------------+
| id | select_type | table      | type  | possible_keys | key     | key_len | ref  | rows  | Extra       |
+----+-------------+------------+-------+---------------+---------+---------+------+-------+-------------+
|  1 | PRIMARY     | <derived2> | ALL   | NULL          | NULL    | NULL    | NULL | 40000 |             | 
|  2 | DERIVED     | actor_1    | index | NULL          | PRIMARY | 2       | NULL |   200 | Using index | 
|  2 | DERIVED     | actor_2    | index | NULL          | PRIMARY | 2       | NULL |   200 | Using index | 
+----+-------------+------------+-------+---------------+---------+---------+------+-------+-------------+
