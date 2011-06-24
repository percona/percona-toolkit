mysql> explain select * from sakila.film where original_language_id = 3 or original_language_id is null;
+----+-------------+-------+-------------+-----------------------------+-----------------------------+---------+-------+------+-------------+
| id | select_type | table | type        | possible_keys               | key                         | key_len | ref   | rows | Extra       |
+----+-------------+-------+-------------+-----------------------------+-----------------------------+---------+-------+------+-------------+
|  1 | SIMPLE      | film  | ref_or_null | idx_fk_original_language_id | idx_fk_original_language_id | 2       | const |  512 | Using where | 
+----+-------------+-------+-------------+-----------------------------+-----------------------------+---------+-------+------+-------------+
1 row in set (0.00 sec)

mysql> notee
