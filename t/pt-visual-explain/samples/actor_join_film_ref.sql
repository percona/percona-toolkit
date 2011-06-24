mysql> explain select * from sakila.film_actor join sakila.film using(film_id);
+----+-------------+------------+------+----------------+----------------+---------+---------------------+------+-------+
| id | select_type | table      | type | possible_keys  | key            | key_len | ref                 | rows | Extra |
+----+-------------+------------+------+----------------+----------------+---------+---------------------+------+-------+
|  1 | SIMPLE      | film       | ALL  | PRIMARY        | NULL           | NULL    | NULL                |  952 |       | 
|  1 | SIMPLE      | film_actor | ref  | idx_fk_film_id | idx_fk_film_id | 2       | sakila.film.film_id |    2 |       | 
+----+-------------+------------+------+----------------+----------------+---------+---------------------+------+-------+
2 rows in set (0.00 sec)

mysql> notee
