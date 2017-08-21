var coll = db.coll

for (i = 0; i < 10; ++i) {
    coll.insert({a: i});
}

coll.count({});
