mysql> explain select distinct film.* from sakila.film join sakila.film_actor using(film_id) where film.film_id % 5 = 0;
+----+-------------+------------+------+----------------+----------------+---------+---------------------+------+------------------------------+
| id | select_type | table      | type | possible_keys  | key            | key_len | ref                 | rows | Extra                        |
+----+-------------+------------+------+----------------+----------------+---------+---------------------+------+------------------------------+
|  1 | SIMPLE      | film       | ALL  | PRIMARY        | NULL           | NULL    | NULL                |  951 | Using where; Using temporary | 
|  1 | SIMPLE      | film_actor | ref  | idx_fk_film_id | idx_fk_film_id | 2       | sakila.film.film_id |    2 | Using index; Distinct        | 
+----+-------------+------------+------+----------------+----------------+---------+---------------------+------+------------------------------+
2 rows in set (0.00 sec)

mysql> notee
