mysql> explain select count(*) from sakila.film_actor where actor_id in(select actor_id from sakila.actor);
+----+--------------------+------------+-----------------+---------------+----------------+---------+------+------+--------------------------+
| id | select_type        | table      | type            | possible_keys | key            | key_len | ref  | rows | Extra                    |
+----+--------------------+------------+-----------------+---------------+----------------+---------+------+------+--------------------------+
|  1 | PRIMARY            | film_actor | index           | NULL          | idx_fk_film_id | 2       | NULL | 5143 | Using where; Using index | 
|  2 | DEPENDENT SUBQUERY | actor      | unique_subquery | PRIMARY       | PRIMARY        | 2       | func |    1 | Using index              | 
+----+--------------------+------------+-----------------+---------------+----------------+---------+------+------+--------------------------+
2 rows in set (0.01 sec)

mysql> notee
