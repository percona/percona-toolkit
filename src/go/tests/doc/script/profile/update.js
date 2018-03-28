var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({a: i});
}
coll.createIndex({a: 1});

coll.update({a: {$gte: 2}}, {$set: {c: 1}, $inc: {a: -10}});
