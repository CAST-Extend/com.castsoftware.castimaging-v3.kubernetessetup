LOAD CSV WITH HEADERS FROM 'file:///techtreeContainer.csv' AS row
WITH row.parent AS Level1 ,row.level0 AS Level2 ,row.level1 AS Level3,row.level2 AS Level4 , row.level3 AS Level5
WITH DISTINCT Level1,Level2,Level3,Level4,Level5
MERGE(t:`ApplicationName`:Technology:level1{technologyName:Level1})
MERGE (t1:`ApplicationName`:Technology:level2{technologyName:Level2})
MERGE (t)-[:Aggregates]->(t1);

