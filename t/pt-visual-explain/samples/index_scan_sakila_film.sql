mysql> explain select * from sakila.film order by title;
+----+-------------+-------+-------+---------------+-----------+---------+------+------+-------+
| id | select_type | table | type  | possible_keys | key       | key_len | ref  | rows | Extra |
+----+-------------+-------+-------+---------------+-----------+---------+------+------+-------+
|  1 | SIMPLE      | film  | index | NULL          | idx_title | 767     | NULL |  952 |       | 
+----+-------------+-------+-------+---------------+-----------+---------+------+------+-------+
1 row in set (0.00 sec)

mysql> notee
