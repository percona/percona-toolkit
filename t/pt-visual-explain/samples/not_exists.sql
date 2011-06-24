mysql> explain select film.film_id from sakila.film left join sakila.film_actor using(film_id) where film_actor.film_id is null;
+----+-------------+------------+-------+----------------+--------------------+---------+---------------------+------+--------------------------------------+
| id | select_type | table      | type  | possible_keys  | key                | key_len | ref                 | rows | Extra                                |
+----+-------------+------------+-------+----------------+--------------------+---------+---------------------+------+--------------------------------------+
|  1 | SIMPLE      | film       | index | NULL           | idx_fk_language_id | 1       | NULL                |  951 | Using index                          | 
|  1 | SIMPLE      | film_actor | ref   | idx_fk_film_id | idx_fk_film_id     | 2       | sakila.film.film_id |    2 | Using where; Using index; Not exists | 
+----+-------------+------------+-------+----------------+--------------------+---------+---------------------+------+--------------------------------------+
2 rows in set (0.00 sec)

mysql> notee
