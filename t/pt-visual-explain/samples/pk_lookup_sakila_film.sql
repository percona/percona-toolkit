mysql> explain select film_id from sakila.film where film_id = 1;
+----+-------------+-------+-------+---------------+---------+---------+-------+------+-------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref   | rows | Extra       |
+----+-------------+-------+-------+---------------+---------+---------+-------+------+-------------+
|  1 | SIMPLE      | film  | const | PRIMARY       | PRIMARY | 2       | const |    1 | Using index | 
+----+-------------+-------+-------+---------------+---------+---------+-------+------+-------------+
1 row in set (0.00 sec)

mysql> notee
