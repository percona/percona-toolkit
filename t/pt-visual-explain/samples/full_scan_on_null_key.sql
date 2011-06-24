EXPLAIN
SELECT * FROM t1
WHERE t1.id NOT IN (SELECT t2.id FROM t2,t3 
WHERE t3.name='xxx' AND t2.id=t3.id);
id	select_type	table	type	possible_keys	key	key_len	ref	rows	Extra
1	PRIMARY	t1	ALL	NULL	NULL	NULL	NULL	4	Using where
2	DEPENDENT SUBQUERY	t2	eq_ref	PRIMARY	PRIMARY	4	func	1	Using where; Using index; Full scan on NULL key
2	DEPENDENT SUBQUERY	t3	eq_ref	PRIMARY	PRIMARY	4	func	1	Using where; Full scan on NULL key
