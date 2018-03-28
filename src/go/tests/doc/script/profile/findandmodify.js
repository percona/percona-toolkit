var coll = db.coll;
coll.drop();

for (var i = 0; i < 3; i++) {
    coll.insert({_id: i, a: i, b: i});
}
coll.createIndex({b: 1});

coll.findAndModify({
    query: {a: 2},
    update: {$inc: {"b": 1}}
});
