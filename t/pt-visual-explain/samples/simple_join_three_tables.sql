mysql> explain select actor_1.actor_id from sakila.actor as actor_1 inner join sakila.actor as actor_2 using(actor_id) inner join sakila.actor as actor_3 using(actor_id);
+----+-------------+---------+--------+---------------+---------+---------+-------------------------+------+-------------+
| id | select_type | table   | type   | possible_keys | key     | key_len | ref                     | rows | Extra       |
+----+-------------+---------+--------+---------------+---------+---------+-------------------------+------+-------------+
|  1 | SIMPLE      | actor_1 | index  | PRIMARY       | PRIMARY | 2       | NULL                    |  200 | Using index | 
|  1 | SIMPLE      | actor_2 | eq_ref | PRIMARY       | PRIMARY | 2       | sakila.actor_1.actor_id |    1 | Using index | 
|  1 | SIMPLE      | actor_3 | eq_ref | PRIMARY       | PRIMARY | 2       | sakila.actor_1.actor_id |    1 | Using index | 
+----+-------------+---------+--------+---------------+---------+---------+-------------------------+------+-------------+
3 rows in set (0.00 sec)

mysql> notee
