CALL apoc.periodic.iterate(
     "MATCH (tt:TransactionTechnology:`ApplicationName`) RETURN tt",
     "MATCH (tt)<-[:HAS_TECHNOLOGY]-(:Transaction:`ApplicationName`)-[:TransactionContains]->(o:Object)
       WHERE o.type = tt.technologyName
       WITH tt, o
         MERGE (tt)-[:CONTAINS_OBJECT]->(o)",
     {batchSize:1, parallel:true, iterateList:true, retries:3}
 );
