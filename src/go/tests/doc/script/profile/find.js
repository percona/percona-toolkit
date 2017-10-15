var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({k: i % 5});
}
coll.createIndex({k: 1});

coll.find({k: 1}).toArray();
