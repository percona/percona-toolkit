mysql> explain select language_id from sakila.film group by language_id;
+----+-------------+-------+-------+---------------+--------------------+---------+------+------+--------------------------+
| id | select_type | table | type  | possible_keys | key                | key_len | ref  | rows | Extra                    |
+----+-------------+-------+-------+---------------+--------------------+---------+------+------+--------------------------+
|  1 | SIMPLE      | film  | range | NULL          | idx_fk_language_id | 1       | NULL |    2 | Using index for group-by | 
+----+-------------+-------+-------+---------------+--------------------+---------+------+------+--------------------------+
1 row in set (0.00 sec)

mysql> notee
