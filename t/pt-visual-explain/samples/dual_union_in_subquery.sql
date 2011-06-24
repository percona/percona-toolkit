mysql> explain select 1 in (select 1 union select 2);
+----+--------------------+------------+------+---------------+------+---------+------+------+----------------+
| id | select_type        | table      | type | possible_keys | key  | key_len | ref  | rows | Extra          |
+----+--------------------+------------+------+---------------+------+---------+------+------+----------------+
|  1 | PRIMARY            | NULL       | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  2 | DEPENDENT SUBQUERY | NULL       | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  3 | DEPENDENT UNION    | NULL       | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| NULL | UNION RESULT       | <union2,3> | ALL  | NULL          | NULL | NULL    | NULL | NULL |                | 
+----+--------------------+------------+------+---------------+------+---------+------+------+----------------+
4 rows in set (0.00 sec)

mysql> notee
