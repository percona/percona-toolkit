explain select key1,key2,key3,key4,filler1 from t1 where key1=100 and key2=100 or key3=100 and key4=100;
id	select_type	table	type	possible_keys	key	key_len	ref	rows	Extra
1	SIMPLE	t1	index_merge	key1,key2,key3,key4	key1,key2,key3,key4	5,5,5,5	NULL	154	Using union(intersect(key1,key2),intersect(key3,key4)); Using where
