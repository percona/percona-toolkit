mysql> explain select film.film_id, count(*) from sakila.film join sakila.film_actor using(film_id) join sakila.actor using(actor_id) group by film.film_id order by count(*) desc;
+----+-------------+------------+--------+------------------------+---------+---------+---------------------------+------+----------------------------------------------+
| id | select_type | table      | type   | possible_keys          | key     | key_len | ref                       | rows | Extra                                        |
+----+-------------+------------+--------+------------------------+---------+---------+---------------------------+------+----------------------------------------------+
|  1 | SIMPLE      | actor      | index  | PRIMARY                | PRIMARY | 2       | NULL                      |  200 | Using index; Using temporary; Using filesort | 
|  1 | SIMPLE      | film_actor | ref    | PRIMARY,idx_fk_film_id | PRIMARY | 2       | sakila.actor.actor_id     |   13 | Using index                                  | 
|  1 | SIMPLE      | film       | eq_ref | PRIMARY                | PRIMARY | 2       | sakila.film_actor.film_id |    1 | Using index                                  | 
+----+-------------+------------+--------+------------------------+---------+---------+---------------------------+------+----------------------------------------------+
3 rows in set (0.00 sec)

mysql> 