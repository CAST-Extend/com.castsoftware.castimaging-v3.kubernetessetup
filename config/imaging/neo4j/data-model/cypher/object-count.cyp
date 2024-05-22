CALL apoc.periodic.iterate(
"MATCH(t:Transaction) RETURN t",
"MATCH(t)-[r:TransactionContains|TRANSACTION_STARTPOINT|TRANSACTION_ENDPOINT]-(o:Object)
WITH t,count(distinct(o)) AS count
SET t.objectCount = count",
{batchSize:500, parallel:false, iterateList:true, retries:3}
);
