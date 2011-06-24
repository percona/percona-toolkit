explain select * from t1,t2,t3 where t2.key1 = t1.col1 and t3.key1<40;
+----+-------------+-------+-------+---------------+------+---------+--------------+------+--------------------------------+
| id | select_type | table | type  | possible_keys | key  | key_len | ref          | rows | Extra                          |
+----+-------------+-------+-------+---------------+------+---------+--------------+------+--------------------------------+
|  1 | SIMPLE      | t1    | ALL   | NULL          | NULL | NULL    | NULL         |   10 |                                |
|  1 | SIMPLE      | t2    | ref   | key1          | key1 | 5       | test.t1.col1 |    2 | Using where                    |
|  1 | SIMPLE      | t3    | range | key1          | key1 | 5       | NULL         |   40 | Using where; Using join buffer |
+----+-------------+-------+-------+---------------+------+---------+--------------+------+--------------------------------+
