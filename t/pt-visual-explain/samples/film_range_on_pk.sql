mysql> explain select * from sakila.film where film_id between 1 and 20;
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
|  1 | SIMPLE      | film  | range | PRIMARY       | PRIMARY | 2       | NULL |   20 | Using where | 
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
1 row in set (0.00 sec)

mysql> notee
