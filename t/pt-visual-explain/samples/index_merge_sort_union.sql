explain select * from t0 where key1 < 3 or key2 > 1020;
id	select_type	table	type	possible_keys	key	key_len	ref	rows	Extra
1	SIMPLE	t0	index_merge	i1,i2	i1,i2	4,4	NULL	45	Using sort_union(i1,i2); Using where
