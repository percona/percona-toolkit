explain
select actor_id from (
   select actor_id from sakila.actor
) as der_1
union
select film_id from (
   select film_id from sakila.film
) as der_2;
+----+--------------+------------+-------+---------------+--------------------+---------+------+------+-------------+
| id | select_type  | table      | type  | possible_keys | key                | key_len | ref  | rows | Extra       |
+----+--------------+------------+-------+---------------+--------------------+---------+------+------+-------------+
|  1 | PRIMARY      | <derived2> | ALL   | NULL          | NULL               | NULL    | NULL |  200 |             | 
|  2 | DERIVED      | actor      | index | NULL          | PRIMARY            | 2       | NULL |  200 | Using index | 
|  3 | UNION        | <derived4> | ALL   | NULL          | NULL               | NULL    | NULL | 1000 |             | 
|  4 | DERIVED      | film       | index | NULL          | idx_fk_language_id | 1       | NULL |  951 | Using index | 
| NULL | UNION RESULT | <union1,3> | ALL   | NULL          | NULL               | NULL    | NULL | NULL |             | 
+----+--------------+------------+-------+---------------+--------------------+---------+------+------+-------------+
