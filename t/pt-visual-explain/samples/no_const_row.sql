mysql> create table test.t1(a int, b int);
Query OK, 0 rows affected (0.04 sec)

mysql> create view test.v1(c, d) as select a+1,b+1 from test.t1;
Query OK, 0 rows affected (0.00 sec)

mysql> explain select c from test.v1;
+----+-------------+-------+--------+---------------+------+---------+------+------+---------------------+
| id | select_type | table | type   | possible_keys | key  | key_len | ref  | rows | Extra               |
+----+-------------+-------+--------+---------------+------+---------+------+------+---------------------+
|  1 | SIMPLE      | t1    | system | NULL          | NULL | NULL    | NULL |    0 | const row not found | 
+----+-------------+-------+--------+---------------+------+---------+------+------+---------------------+
