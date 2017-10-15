var coll = db.coll;
coll.drop();

var mapFunction = function() {
    emit(this.a, this.b);
};

var reduceFunction = function(a, b) {
    return Array.sum(b);
};

for (var i = 0; i < 3; i++) {
    coll.insert({a: i, b: i});
}
coll.createIndex({a: 1});

coll.mapReduce(mapFunction,
               reduceFunction,
               {query: {a: {$gte: 0}}, out: {inline: 1}});
