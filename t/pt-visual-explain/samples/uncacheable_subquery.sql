mysql> explain select actor_id, (select @foo := coalesce(@foo, 0) + 1 from sakila.actor) as foo from sakila.actor;
+----+----------------------+-------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type          | table | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+----------------------+-------+-------+---------------+---------+---------+------+------+-------------+
|  1 | PRIMARY              | actor | index | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
|  2 | UNCACHEABLE SUBQUERY | actor | index | NULL          | PRIMARY | 2       | NULL |  200 | Using index | 
+----+----------------------+-------+-------+---------------+---------+---------+------+------+-------------+
2 rows in set (0.00 sec)

mysql> notee
