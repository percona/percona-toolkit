mysql> explain select * from (select * from sakila.film_actor where film_id = 1) as x;
+----+-------------+------------+------+----------------+----------------+---------+------+------+-------+
| id | select_type | table      | type | possible_keys  | key            | key_len | ref  | rows | Extra |
+----+-------------+------------+------+----------------+----------------+---------+------+------+-------+
|  1 | PRIMARY     | <derived2> | ALL  | NULL           | NULL           | NULL    | NULL |   10 |       | 
|  2 | DERIVED     | film_actor | ref  | idx_fk_film_id | idx_fk_film_id | 2       |      |   10 |       | 
+----+-------------+------------+------+----------------+----------------+---------+------+------+-------+
2 rows in set (0.01 sec)

mysql> notee
