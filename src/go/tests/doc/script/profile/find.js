var coll = db.coll

coll.createIndex({a: 1})
coll.find({a: 1})
