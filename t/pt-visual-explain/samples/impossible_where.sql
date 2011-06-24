mysql> explain select * from sakila.film where film_id between 5 and 4;
+----+-------------+-------+------+---------------+------+---------+------+------+-----------------------------------------------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra                                               |
+----+-------------+-------+------+---------------+------+---------+------+------+-----------------------------------------------------+
|  1 | SIMPLE      | NULL  | NULL | NULL          | NULL | NULL    | NULL | NULL | Impossible WHERE noticed after reading const tables | 
+----+-------------+-------+------+---------------+------+---------+------+------+-----------------------------------------------------+
1 row in set (0.01 sec)

mysql> notee
