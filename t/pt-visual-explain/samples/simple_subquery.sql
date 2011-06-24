mysql> explain select actor_id, (select count(film_id) from sakila.film) from sakila.actor;
+----+-------------+-------+-------+---------------+--------------------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key                | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+--------------------+---------+------+------+-------------+
|  1 | PRIMARY     | actor | index | NULL          | PRIMARY            | 2       | NULL |  200 | Using index | 
|  2 | SUBQUERY    | film  | index | NULL          | idx_fk_language_id | 1       | NULL |  951 | Using index | 
+----+-------------+-------+-------+---------------+--------------------+---------+------+------+-------------+
2 rows in set (0.00 sec)

mysql> notee
