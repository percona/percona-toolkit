var coll = db.coll;
coll.drop();

coll.find({
    $and: [
          {
            k: { $gt: 1 }
          },
          {
            k: { $lt: 2 }
          },
          {
            $or: [
              {
                c: { $in: [/^0/, /^2/, /^4/, /^6/] }
              },
              {
                pad: { $in: [/9$/, /7$/, /5$/, /3$/] }
              }
            ]
          }
        ]
}).sort({ k: -1 }).limit(100).toArray();
