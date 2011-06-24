mysql> explain select 1 as foo union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1 union all select 1;
+----+--------------+---------------------------------------------------------------+------+---------------+------+---------+------+------+----------------+
| id | select_type  | table                                                         | type | possible_keys | key  | key_len | ref  | rows | Extra          |
+----+--------------+---------------------------------------------------------------+------+---------------+------+---------+------+------+----------------+
|  1 | PRIMARY      | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  2 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  3 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  4 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  5 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  6 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  7 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  8 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
|  9 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 10 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 11 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 12 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 13 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 14 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 15 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 16 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 17 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 18 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 19 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 20 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 21 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| 22 | UNION        | NULL                                                          | NULL | NULL          | NULL | NULL    | NULL | NULL | No tables used | 
| NULL | UNION RESULT | <union1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,...> | ALL  | NULL          | NULL | NULL    | NULL | NULL |                | 
+----+--------------+---------------------------------------------------------------+------+---------------+------+---------+------+------+----------------+
23 rows in set (0.00 sec)

mysql> notee
