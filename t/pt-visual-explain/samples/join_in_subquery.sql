explain
select actor_id, 
   (select count(film_id) from sakila.film join sakila.film_actor using(film_id))
from sakila.actor;
+----+-------------+------------+-------+----------------+--------------------+---------+---------------------+------+-------------+
| id | select_type | table      | type  | possible_keys  | key                | key_len | ref                 | rows | Extra       |
+----+-------------+------------+-------+----------------+--------------------+---------+---------------------+------+-------------+
|  1 | PRIMARY     | actor      | index | NULL           | PRIMARY            | 2       | NULL                |  200 | Using index | 
|  2 | SUBQUERY    | film       | index | PRIMARY        | idx_fk_language_id | 1       | NULL                |  951 | Using index | 
|  2 | SUBQUERY    | film_actor | ref   | idx_fk_film_id | idx_fk_film_id     | 2       | sakila.film.film_id |    2 | Using index | 
+----+-------------+------------+-------+----------------+--------------------+---------+---------------------+------+-------------+
3 rows in set (0.00 sec)

mysql> notee
