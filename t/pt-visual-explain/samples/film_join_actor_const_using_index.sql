mysql> explain select film_id from sakila.film join sakila.film_actor using(film_id) where sakila.film.film_id = 1;
+----+-------------+------------+-------+----------------+----------------+---------+-------+------+-------------+
| id | select_type | table      | type  | possible_keys  | key            | key_len | ref   | rows | Extra       |
+----+-------------+------------+-------+----------------+----------------+---------+-------+------+-------------+
|  1 | SIMPLE      | film       | const | PRIMARY        | PRIMARY        | 2       | const |    1 | Using index | 
|  1 | SIMPLE      | film_actor | ref   | idx_fk_film_id | idx_fk_film_id | 2       | const |   10 | Using index | 
+----+-------------+------------+-------+----------------+----------------+---------+-------+------+-------------+
2 rows in set (0.00 sec)

mysql> notee
