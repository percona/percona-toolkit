var coll = db.coll

coll.createIndex({a: 1})

var i;
for (i = 0; i < 10; ++i) {
    coll.insert({a: i % 5});
}

coll.find({a: 1}).pretty()
