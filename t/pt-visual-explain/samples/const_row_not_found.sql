mysql> CREATE TABLE t1 (i INT);
mysql> explain select * from t1 where not exists ((select t11.i from t1 t11) union (select t12.i from t1 t12));
+----+--------------+------------+--------+---------------+------+---------+------+------+--------------------------------+
| id | select_type  | table      | type   | possible_keys | key  | key_len | ref  | rows | Extra                          |
+----+--------------+------------+--------+---------------+------+---------+------+------+--------------------------------+
|  1 | PRIMARY      | t1         | system | NULL          | NULL | NULL    | NULL |    0 | const row not found            | 
|  2 | SUBQUERY     | NULL       | NULL   | NULL          | NULL | NULL    | NULL | NULL | No tables used                 | 
|  3 | SUBQUERY     | NULL       | NULL   | NULL          | NULL | NULL    | NULL | NULL | no matching row in const table | 
|  4 | UNION        | t12        | system | NULL          | NULL | NULL    | NULL |    0 | const row not found            | 
| NULL | UNION RESULT | <union2,4> | ALL    | NULL          | NULL | NULL    | NULL | NULL |                                | 
+----+--------------+------------+--------+---------------+------+---------+------+------+--------------------------------+
