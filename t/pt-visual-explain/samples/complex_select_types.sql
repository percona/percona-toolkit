EXPLAIN
SELECT actor_id,
   (SELECT 1 FROM sakila.film_actor WHERE film_actor.actor_id = der_1.actor_id LIMIT 1)
FROM (
   SELECT actor_id FROM sakila.actor LIMIT 5
) AS der_1
UNION
SELECT film_id, (SELECT @var1 FROM sakila.rental LIMIT 1) FROM (
   SELECT film_id, (SELECT 1 FROM sakila.store LIMIT 1) FROM sakila.film LIMIT 5
) AS der_2;

+----+----------------------+------------+-------+---------------+--------------------+---------+----------------+-------+-------------+
| id | select_type          | table      | type  | possible_keys | key                | key_len | ref            | rows  | Extra       |
+----+----------------------+------------+-------+---------------+--------------------+---------+----------------+-------+-------------+
|  1 | PRIMARY              | <derived3> | ALL   | NULL          | NULL               | NULL    | NULL           |     5 |             | 
|  3 | DERIVED              | actor      | index | NULL          | PRIMARY            | 2       | NULL           |   200 | Using index | 
|  2 | DEPENDENT SUBQUERY   | film_actor | ref   | PRIMARY       | PRIMARY            | 2       | der_1.actor_id |    13 | Using index | 
|  4 | UNION                | <derived6> | ALL   | NULL          | NULL               | NULL    | NULL           |     5 |             | 
|  6 | DERIVED              | film       | index | NULL          | idx_fk_language_id | 1       | NULL           |  1022 | Using index | 
|  7 | SUBQUERY             | store      | index | NULL          | PRIMARY            | 1       | NULL           |     2 | Using index | 
|  5 | UNCACHEABLE SUBQUERY | rental     | index | NULL          | idx_fk_staff_id    | 1       | NULL           | 16305 | Using index | 
| NULL | UNION RESULT         | <union1,4> | ALL   | NULL          | NULL               | NULL    | NULL           |  NULL |             | 
+----+----------------------+------------+-------+---------------+--------------------+---------+----------------+-------+-------------+
