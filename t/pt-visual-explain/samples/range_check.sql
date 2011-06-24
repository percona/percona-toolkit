EXPLAIN
SELECT s.oxid FROM t1 v, t1 s 
WHERE s.oxrootid = 'd8c4177d09f8b11f5.52725521' AND
v.oxrootid ='d8c4177d09f8b11f5.52725521' AND
s.oxleft > v.oxleft AND s.oxleft < v.oxright;
id	select_type	table	type	possible_keys	key	key_len	ref	rows	Extra
1	SIMPLE	v	ref	OXLEFT,OXRIGHT,OXROOTID	OXROOTID	32	const	5	Using where
1	SIMPLE	s	ALL	OXLEFT	NULL	NULL	NULL	5	Range checked for each record (index map: 0x4)
