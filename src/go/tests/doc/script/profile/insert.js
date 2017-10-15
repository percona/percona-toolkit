var coll = db.coll;
coll.drop();

var doc = {_id: 1};
var result = coll.insert(doc);
