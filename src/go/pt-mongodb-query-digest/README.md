#pt-mongodb-query-digest

This program reports query usage statistics by aggregating queries from MongoDB query profiler.  
The queries are the result of running:
```javascript
db.getSiblingDB("samples").system.profile.find({"op":{"$nin":["getmore", "delete"]}});
```
and then, the results are grouped by fingerprint and namespace (database.collection).

The fingerprint is calculated as the **sorted list** of the keys in the document. The max depth level is 10.  
The last step is sorting the results. The default sort order is by ascending query count.  

##Sample output
```
# Query 3:  0.06 QPS, ID 0b906bd86148def663d11b402f3e41fa
# Ratio    1.00  (docs scanned/returned)
# Time range: 2017-02-03 16:01:37.484 -0300 ART to 2017-02-03 16:02:08.43 -0300 ART
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count (docs)                   100
# Exec Time ms           2         3           0           1           0           0           0           0
# Docs Scanned           5      7.50K      75.00       75.00       75.00       75.00        0.00       75.00
# Docs Returned         92      7.50K      75.00       75.00       75.00       75.00        0.00       75.00
# Bytes recv             1    106.12M       1.06M       1.06M       1.06M       1.06M       0.00        1.06M
# String:
# Namespaces          samples.col1
# Operation           query
# Fingerprint         find,shardVersion
# Query               {"find":"col1","shardVersion":[0,"000000000000000000000000"]}

```
  
##Command line parameters  
  
|Short|Long|Help|
|-----|----|----|
|-?|--help|Show help|
|-a|--authenticationDatabase|database used to establish credentials and privileges with a MongoDB server admin|
|-c|--no-version-check|Don't check for updates|
|-d|--database|database to profile|
|-l|--log-level|Log level:, panic, fatal, error, warn, info, debug error|
|-n|--limit|show the first n queries|
|-o|--order-by|comma separated list of order by fields (max values): `count`, `ratio`, `query-time`, `docs-scanned`, `docs-returned`.<br> A `-` in front of the field name denotes reverse order.<br> Example:`--order-by="count,-ratio"`).|
|-p|--password[=password]|Password (optional). If it is not specified it will be asked|
|-s|--skip-collections|Comma separated list of collections to skip. Default: `system.profile`. It is possible to use an empty list by setting `--skip-collections=""`|
|-u|--user|Username|
|-v|--version|Show version & exit|

