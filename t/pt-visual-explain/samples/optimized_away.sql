mysql> explain select min(film_id) from sakila.film;
+----+-------------+-------+------+---------------+------+---------+------+------+------------------------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra                        |
+----+-------------+-------+------+---------------+------+---------+------+------+------------------------------+
|  1 | SIMPLE      | NULL  | NULL | NULL          | NULL | NULL    | NULL | NULL | Select tables optimized away | 
+----+-------------+-------+------+---------------+------+---------+------+------+------------------------------+
1 row in set (0.00 sec)

mysql> notee
