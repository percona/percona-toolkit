explain select *,
   (select count(*) from sakila.film as outer_sub where outer_sub.film_id = outer_der.film_id)
from (
   select *,
      (select count(*) from sakila.film as mid_sub where mid_sub.film_id = mid_der.film_id)
   from (
      select *,
         (select count(*) from sakila.film as inner_sub where inner_sub.film_id = inner_der.film_id)
      from sakila.film as inner_der
   ) as mid_der
) as outer_der;

+----+--------------------+------------+--------+---------------+---------+---------+-------------------+------+--------------------------+
| id | select_type        | table      | type   | possible_keys | key     | key_len | ref               | rows | Extra                    |
+----+--------------------+------------+--------+---------------+---------+---------+-------------------+------+--------------------------+
|  1 | PRIMARY            | <derived3> | ALL    | NULL          | NULL    | NULL    | NULL              | 1000 |                          | 
|  3 | DERIVED            | <derived5> | ALL    | NULL          | NULL    | NULL    | NULL              | 1000 |                          | 
|  5 | DERIVED            | inner_der  | ALL    | NULL          | NULL    | NULL    | NULL              |  951 |                          | 
|  6 | DEPENDENT SUBQUERY | inner_sub  | eq_ref | PRIMARY       | PRIMARY | 2       | inner_der.film_id |    1 | Using where; Using index | 
|  4 | DEPENDENT SUBQUERY | mid_sub    | eq_ref | PRIMARY       | PRIMARY | 2       | mid_der.film_id   |    1 | Using where; Using index | 
|  2 | DEPENDENT SUBQUERY | outer_sub  | eq_ref | PRIMARY       | PRIMARY | 2       | outer_der.film_id |    1 | Using where; Using index | 
+----+--------------------+------------+--------+---------------+---------+---------+-------------------+------+--------------------------+
