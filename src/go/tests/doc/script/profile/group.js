var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({a: i, b: i % 5});
}
coll.createIndex({b: -1});

coll.group({
    key: {a: 1, b: 1},
    cond: {b: 3},
    reduce: function() {},
    initial: {}
});
