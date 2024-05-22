CALL apoc.periodic.iterate(
  "MATCH (t:Transaction:`ApplicationName`) RETURN t",
  "MATCH
      (t)-[r1:HAS_TECHNOLOGY]->(tt1:TransactionTechnology),
      (t)-[r21:HAS_TECHNOLOGY]->(tt2:TransactionTechnology)
    WHERE (tt1)-[:CONTAINS_OBJECT]->(:Object)-[:References]->(:Object)<-[:CONTAINS_OBJECT]-(tt2)
    WITH tt1, tt2, count (*) AS count
      MERGE (tt1)-[r:References]->(tt2) ON CREATE SET r.count=count",
  { batchSize:500, parallel:false, iterateList:true, retries:3 }
);
