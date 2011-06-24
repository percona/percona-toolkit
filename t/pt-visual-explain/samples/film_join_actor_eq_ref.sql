mysql> explain select straight_join * from sakila.film_actor join sakila.film using(film_id);
+----+-------------+------------+--------+----------------+---------+---------+---------------------------+------+-------+
| id | select_type | table      | type   | possible_keys  | key     | key_len | ref                       | rows | Extra |
+----+-------------+------------+--------+----------------+---------+---------+---------------------------+------+-------+
|  1 | SIMPLE      | film_actor | ALL    | idx_fk_film_id | NULL    | NULL    | NULL                      | 5143 |       | 
|  1 | SIMPLE      | film       | eq_ref | PRIMARY        | PRIMARY | 2       | sakila.film_actor.film_id |    1 |       | 
+----+-------------+------------+--------+----------------+---------+---------+---------------------------+------+-------+
2 rows in set (0.00 sec)

mysql> notee
