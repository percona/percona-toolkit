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
# Query 2:  0.00 QPS, ID 1a6443c2db9661f3aad8edb6b877e45d
# Ratio    1.00  (docs scanned/returned)
# Time range: 2017-01-11 12:58:26.519 -0300 ART to 2017-01-11 12:58:26.686 -0300 ART
# Attribute            pct     total        min         max        avg         95%        stddev      median
# ==================   ===   ========    ========    ========    ========    ========     =======    ========
# Count (docs)                    36 
# Exec Time ms           0         0           0           0           0           0           0           0 
# Docs Scanned           0    148.00        0.00       74.00        4.11       74.00       16.95        0.00 
# Docs Returned          2    148.00        0.00       74.00        4.11       74.00       16.95        0.00 
# Bytes recv             0      2.11M     215.00        1.05M      58.48K       1.05M     240.22K     215.00 
# String:
# Namespaces          samples.col1
# Fingerprint         $gte,$lt,$meta,$sortKey,filter,find,projection,shardVersion,sort,user_id,user_id
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
|-u|--user|Username|
|-v|--version|Show version & exit|

