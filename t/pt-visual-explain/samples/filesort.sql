mysql> notee
mysql> explain select language_id from sakila.film order by last_update;
+----+-------------+-------+------+---------------+------+---------+------+------+----------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra          |
+----+-------------+-------+------+---------------+------+---------+------+------+----------------+
|  1 | SIMPLE      | film  | ALL  | NULL          | NULL | NULL    | NULL |  951 | Using filesort | 
+----+-------------+-------+------+---------------+------+---------+------+------+----------------+
1 row in set (0.00 sec)

mysql> notee
