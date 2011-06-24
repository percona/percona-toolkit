mysql> drop table if exists t1, t2;
Query OK, 0 rows affected (0.00 sec)

mysql> create table t1 (a1 int, a2 char(3), key k1(a1), key k2(a2));
Query OK, 0 rows affected (0.05 sec)

mysql> insert into t1 values(10,'aaa'), (10,null), (10,'bbb'), (20,'zzz');
Query OK, 4 rows affected (0.00 sec)
Records: 4  Duplicates: 0  Warnings: 0

mysql> create table t2(a1 char(3), a2 int, a3 real, key k1(a1), key k2(a2, a1));
Query OK, 0 rows affected (0.04 sec)

mysql> explain select max(t1.a1), max(t2.a2) from t1, t2;
+----+-------------+-------+------+---------------+------+---------+------+------+-------------------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra                   |
+----+-------------+-------+------+---------------+------+---------+------+------+-------------------------+
|  1 | SIMPLE      | NULL  | NULL | NULL          | NULL | NULL    | NULL | NULL | No matching min/max row | 
+----+-------------+-------+------+---------------+------+---------+------+------+-------------------------+
1 row in set (0.00 sec)

mysql> drop table if exists t1, t2;
Query OK, 0 rows affected (0.00 sec)

mysql> notee;
