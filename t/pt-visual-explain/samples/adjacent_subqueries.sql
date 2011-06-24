explain
select (
   select count(*) from sakila.film_actor
      where sakila.film_actor.actor_id = sakila.actor.actor_id
) + (
   select count(*) from sakila.film as f
) as count_actors from sakila.actor;
+----+--------------------+------------+-------+---------------+--------------------+---------+----------------+------+--------------------------+
| id | select_type        | table      | type  | possible_keys | key                | key_len | ref            | rows | Extra                    |
+----+--------------------+------------+-------+---------------+--------------------+---------+----------------+------+--------------------------+
|  1 | PRIMARY            | actor      | index | NULL          | PRIMARY            | 2       | NULL           |  200 | Using index              | 
|  3 | SUBQUERY           | f          | index | NULL          | idx_fk_language_id | 1       | NULL           |  951 | Using index              | 
|  2 | DEPENDENT SUBQUERY | film_actor | ref   | PRIMARY       | PRIMARY            | 2       | actor.actor_id |   13 | Using where; Using index | 
+----+--------------------+------------+-------+---------------+--------------------+---------+----------------+------+--------------------------+
