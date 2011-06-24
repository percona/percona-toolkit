explain select * from const_tbl, t1, t2 where t1.b=const_tbl.a and t2.a=t1.a order by t1.a;
+----+-------------+-----------+--------+---------------+------+---------+------------+------+----------------+
| id | select_type | table     | type   | possible_keys | key  | key_len | ref        | rows | Extra          |
+----+-------------+-----------+--------+---------------+------+---------+------------+------+----------------+
| 1  | SIMPLE      | const_tbl | system | NULL          | NULL | NULL    | NULL       | 1    | Using filesort |
| 1  | SIMPLE      | t1        | ALL    | NULL          | NULL | NULL    | NULL       | 10   | Using where    |
| 1  | SIMPLE      | t2        | ref    | a             | a    | 5       | test4.t1.a | 11   | Using where    |
+----+-------------+-----------+--------+---------------+------+---------+------------+------+----------------+
