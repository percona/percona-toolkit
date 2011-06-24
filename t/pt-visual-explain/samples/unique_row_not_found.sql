SELECT user.avatarid, user.avatarrevision, avatarpath, NOT
ISNULL(customavatar.userid) AS hascustom, customavatar.dateline,
   customavatar.width, customavatar.height
   FROM user AS user
   LEFT JOIN avatar AS avatar ON avatar.avatarid = user.avatarid
   LEFT JOIN customavatar AS customavatar ON customavatar.userid = user.userid
   WHERE user.userid = 65z

id	select_type	table	type	possible_keys	key	key_len	ref	rows	Extra
1	SIMPLE	user	const	PRIMARY	PRIMARY	4	const	1	
1	SIMPLE	avatar	const	PRIMARY	PRIMARY	2	const	0	unique row not found
1	SIMPLE	customavatar	const	PRIMARY	PRIMARY	4	const	0	unique row not found
