var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({a: i, b: i});
}
coll.createIndex({a: 1});

coll.remove({a: {$gte: 2}, b: {$gte: 2}});
