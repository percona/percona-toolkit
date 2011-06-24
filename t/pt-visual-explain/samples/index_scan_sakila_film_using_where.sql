mysql> explain select * from sakila.film where film_id mod 2 = 0 order by title;
+----+-------------+-------+-------+---------------+-----------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key       | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+-----------+---------+------+------+-------------+
|  1 | SIMPLE      | film  | index | NULL          | idx_title | 767     | NULL |  952 | Using where | 
+----+-------------+-------+-------+---------------+-----------+---------+------+------+-------------+
1 row in set (0.01 sec)

mysql> notee
