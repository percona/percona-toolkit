var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({a: i % 5, b: i});
}
coll.createIndex({b: 1});

coll.distinct("a", {b: {$gte: 5}});
