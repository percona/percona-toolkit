explain select * from t2 LEFT JOIN t on t2.id = t.id AND 1 = 0 WHERE t2.id = 1;
+------+-------------+-------+-------+---------------+------+---------+------+------+-------------------------+
| id   | select_type | table | type  | possible_keys | key  | key_len | ref  | rows | Extra                   |
+------+-------------+-------+-------+---------------+------+---------+------+------+-------------------------+
|    1 | SIMPLE      | t     | const | t_id          | NULL | NULL    | NULL | 0    | Impossible ON condition |
|    1 | SIMPLE      | t2    | ALL   | NULL          | NULL | NULL    | NULL | 1    | Using where             |
+------+-------------+-------+-------+---------------+------+---------+------+------+-------------------------+