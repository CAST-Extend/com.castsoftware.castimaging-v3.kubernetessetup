LOAD CSV WITH HEADERS FROM 'file:///techtreeContainer.csv' AS row
WITH row.parent AS Level1 ,row.level0 AS Level2 ,row.level1 AS Level3 ,row.level2 AS Level4 , row.level3 AS Level5
WITH DISTINCT Level1,Level2,Level3,Level4,Level5
MATCH(t:`ApplicationName`:Technology:level2) WHERE t.technologyName = Level2
MERGE(t1:`ApplicationName`:Technology:level3{technologyName:Level3})
MERGE (t)-[:Aggregates]->(t1);

LOAD CSV WITH HEADERS FROM 'file:///techtreeContainer.csv' AS row
WITH row.parent AS Level1 ,row.level0 AS Level2 ,row.level1 AS Level3 ,row.level2 AS Level4 , row.level3 AS Level5
WITH DISTINCT Level1,Level2,Level3,Level4,Level5
MATCH(t:`ApplicationName`:Technology:level3) WHERE t.technologyName = Level3
MERGE(t1:`ApplicationName`:Technology:level4{technologyName:Level4})
MERGE (t)-[:Aggregates]->(t1);

LOAD CSV WITH HEADERS FROM 'file:///techtreeContainer.csv' AS row
WITH row.parent AS Level1 ,row.level0 AS Level2 ,row.level1 AS Level3 ,row.level2 AS Level4 , row.level3 AS Level5
WITH DISTINCT Level1,Level2,Level3,Level4,Level5
MATCH(t:`ApplicationName`:Technology:level4) WHERE t.technologyName = Level4
MERGE(t1:`ApplicationName`:Technology:level5{technologyName:Level5})
MERGE (t)-[:Aggregates]->(t1);

