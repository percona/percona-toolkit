mysql> explain select * from ( select 1 as foo from sakila.actor ) as x;
+----+-------------+------------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type | table      | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+-------------+------------+-------+---------------+---------+---------+------+------+-------------+
|  1 | PRIMARY     | <derived2> | ALL   | NULL          | NULL    | NULL    | NULL |  200 |             | 
|  2 | DERIVED     | actor      | index | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
+----+-------------+------------+-------+---------------+---------+---------+------+------+-------------+
2 rows in set (0.00 sec)

mysql> notee
