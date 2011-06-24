mysql> explain select 1 from sakila.actor as actor_1 union select 2 from sakila.actor as actor_2;
+----+--------------+------------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type  | table      | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+--------------+------------+-------+---------------+---------+---------+------+------+-------------+
|  1 | PRIMARY      | actor_1    | index | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
|  2 | UNION        | actor_2    | index | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
|    | UNION RESULT | <union1,2> | ALL   | NULL          | NULL    | NULL    | NULL | NULL |             | 
+----+--------------+------------+-------+---------------+---------+---------+------+------+-------------+
