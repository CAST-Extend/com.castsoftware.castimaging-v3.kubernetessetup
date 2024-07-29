LOAD CSV WITH HEADERS FROM 'file:///techtreeObjtype.csv' AS row
WITH row.parent AS Level1 ,row.child AS Level2
WITH DISTINCT Level1,Level2
MATCH(t:`ApplicationName`:Technology:level5) WHERE t.technologyName = Level1
MATCH(ot:`ApplicationName`:ObjectType) WHERE ot.objectType = Level2
MERGE (t)-[:Aggregates]->(ot) ON CREATE SET ot:level6;