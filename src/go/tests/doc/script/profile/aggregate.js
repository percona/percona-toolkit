var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({a: i});
}
coll.createIndex({a: 1});

coll.aggregate([{$match: {a: {$gte: 2}}}]);
