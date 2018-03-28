var coll = db.coll;
coll.drop();

for (var i = 0; i < 10; ++i) {
    coll.insert({a: i, loc: {type: "Point", coordinates: [i, i]}});
}
coll.createIndex({loc: "2dsphere"});

db.runCommand({
    geoNear: "coll",
    near: {type: "Point", coordinates: [1, 1]},
    spherical: true
});

