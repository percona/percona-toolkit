explain select key1,key2,key3 from t1 where key1=100 and key2=100 and key3=100;
id	select_type	table	type	possible_keys	key	key_len	ref	rows	Extra
1	SIMPLE	t1	index_merge	key1,key2,key3	key1,key2,key3	5,5,5	NULL	2	Using intersect(key1,key2,key3); Using where; Using index
