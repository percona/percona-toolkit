var coll = db.coll;
coll.drop();

coll.createIndex({a: 1});

for (var i = 0; i < 10; ++i) {
    coll.insert({a: i % 5});
}

var cursor = coll.find({a: {$gt: 0}}).sort({a: 1}).batchSize(2);
cursor.next();    // Perform initial query and consume first of 2 docs returned.
cursor.next();    // Consume second of 2 docs from initial query.
cursor.next();    // getMore performed, leaving open cursor.
cursor.itcount(); // Exhaust the cursor.
