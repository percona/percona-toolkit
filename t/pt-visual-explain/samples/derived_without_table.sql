EXPLAIN SELECT * FROM (SELECT 1) AS x;
+----+-------------+------------+--------+---------------+------+---------+------+------+----------------+
| id | select_type | table      | type   | possible_keys | key  | key_len | ref  | rows | Extra          |
+----+-------------+------------+--------+---------------+------+---------+------+------+----------------+
|  1 | PRIMARY     | <derived2> | system | NULL          | NULL | NULL    | NULL |    1 |                | 
|  2 | DERIVED     | NULL       | NULL   | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
+----+-------------+------------+--------+---------------+------+---------+------+------+----------------+
