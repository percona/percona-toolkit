mysql> explain select film_id, count(*) from sakila.film group by film_id order by count(*);
+----+-------------+-------+-------+---------------+---------+---------+------+------+----------------------------------------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra                                        |
+----+-------------+-------+-------+---------------+---------+---------+------+------+----------------------------------------------+
|  1 | SIMPLE      | film  | index | NULL          | PRIMARY | 2       | NULL |  951 | Using index; Using temporary; Using filesort | 
+----+-------------+-------+-------+---------------+---------+---------+------+------+----------------------------------------------+
1 row in set (0.00 sec)

mysql> notee
