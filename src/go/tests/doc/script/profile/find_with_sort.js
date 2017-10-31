var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({c: i % 5, b: i});
}
coll.createIndex({c: 1});

coll.find({c: 1}).sort({ b: -1 }).toArray();
