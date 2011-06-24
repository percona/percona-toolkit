explain
select * from (
   select 1 as foo from sakila.actor as actor_1
   union
   select 1 from sakila.actor as actor_2
) as der_1
union
select * from  (
   select 1 as foo from sakila.actor as actor_3
   union all
   select 1 from sakila.actor as actor_4
) as der_2;
+----+--------------+------------+--------+---------------+---------+---------+------+------+-------------+
| id | select_type  | table      | type   | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+--------------+------------+--------+---------------+---------+---------+------+------+-------------+
|  1 | PRIMARY      | <derived2> | system | NULL          | NULL    | NULL    | NULL |    1 |             | 
|  2 | DERIVED      | actor_1    | index  | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
|  3 | UNION        | actor_2    | index  | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
| NULL | UNION RESULT | <union2,3> | ALL    | NULL          | NULL    | NULL    | NULL | NULL |             | 
|  4 | UNION        | <derived5> | ALL    | NULL          | NULL    | NULL    | NULL |  400 |             | 
|  5 | DERIVED      | actor_3    | index  | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
|  6 | UNION        | actor_4    | index  | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
| NULL | UNION RESULT | <union5,6> | ALL    | NULL          | NULL    | NULL    | NULL | NULL |             | 
| NULL | UNION RESULT | <union1,4> | ALL    | NULL          | NULL    | NULL    | NULL | NULL |             | 
+----+--------------+------------+--------+---------------+---------+---------+------+------+-------------+
