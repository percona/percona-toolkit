mysql> explain select actor_id, (select count(*) from sakila.film_actor where film_actor.actor_id = actor.actor_id) from sakila.actor;
+----+--------------------+------------+-------+---------------+---------+---------+----------------+------+--------------------------+
| id | select_type        | table      | type  | possible_keys | key     | key_len | ref            | rows | Extra                    |
+----+--------------------+------------+-------+---------------+---------+---------+----------------+------+--------------------------+
|  1 | PRIMARY            | actor      | index | NULL          | PRIMARY | 2       | NULL           |  200 | Using index              | 
|  2 | DEPENDENT SUBQUERY | film_actor | ref   | PRIMARY       | PRIMARY | 2       | actor.actor_id |   13 | Using where; Using index | 
+----+--------------------+------------+-------+---------------+---------+---------+----------------+------+--------------------------+
2 rows in set (0.00 sec)

mysql> notee
