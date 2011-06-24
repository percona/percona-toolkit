mysql> explain select count(*) from sakila.actor where actor_id in (select actor_id from sakila.film_actor);
+----+--------------------+------------+----------------+---------------+---------+---------+------+------+--------------------------+
| id | select_type        | table      | type           | possible_keys | key     | key_len | ref  | rows | Extra                    |
+----+--------------------+------------+----------------+---------------+---------+---------+------+------+--------------------------+
|  1 | PRIMARY            | actor      | index          | NULL          | PRIMARY | 2       | NULL |  200 | Using where; Using index | 
|  2 | DEPENDENT SUBQUERY | film_actor | index_subquery | PRIMARY       | PRIMARY | 2       | func |   13 | Using index              | 
+----+--------------------+------------+----------------+---------------+---------+---------+------+------+--------------------------+
2 rows in set (0.00 sec)

mysql> notee
