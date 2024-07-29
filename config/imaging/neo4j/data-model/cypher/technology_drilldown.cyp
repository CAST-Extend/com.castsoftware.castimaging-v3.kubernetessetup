#Java

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM 'file:///PGU_Technology_Drill_Down.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE Level2 = "JEE"
AND NOT Level3  CONTAINS 'to ignore'
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8
MERGE(t:Technology:level1{technologyName:Level1})-[:Aggregates]->(t1:Technology:level2{technologyName:Level2})
MERGE(t1)-[:Aggregates]->(t2:Technology:level3{technologyName:Level3})
MERGE(t2)-[:Aggregates]->(t3:Technology:level4{technologyName:Level4})
WITH DISTINCT Level4,Level5,Level6,Level7,Level8,t3,
SPLIT(Level5,';') AS value
UNWIND value AS result 
MATCH (ot:ObjectType)
WHERE ot.objectType = result 
MERGE (t3)-[:Aggregates]->(ot)
set ot:level5
WITH ot,Level5,Level6,Level7,Level8,
SPLIT(Level6,';') AS value WHERE NOT Level5 CONTAINS 'Others'
UNWIND value AS result
MATCH (ot1:ObjectType)
WHERE ot1.objectType = result
MERGE(ot)-[:Aggregates]->(ot1)
set ot1:level6
WITH DISTINCT Level6,Level7,Level8,ot1,
SPLIT(Level7,';') AS value
UNWIND value AS result 
MATCH (ot2:ObjectType)
WHERE ot2.objectType = result
MERGE(ot1)-[:Aggregates]->(ot2)
set ot2:level7
WITH DISTINCT Level7,Level8,ot2,
SPLIT(Level8,';') AS value
UNWIND value AS result
MATCH(ot3:ObjectType)
WHERE ot3.objectType = result
MERGE(ot2)-[:Aggregates]->(ot3)
set ot3:level8 






LOAD CSV WITH HEADERS FROM 'file:///PGU_Technology_Drill_Down.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE Level2 = "JEE"
AND NOT Level3  CONTAINS 'to ignore'
WITH Distinct Level5,Level4,
SPLIT(Level5,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result 
MERGE(t:Technology{technologyName:Level4})-[:Aggregates]->(ot)


#Everything-----Redundant Code

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM 'file:///PGU_Technology_Drill_Down.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level3  CONTAINS 'to ignore'
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8
MERGE(t:Technology:level1{technologyName:Level1})
MERGE (t1:Technology:level2{technologyName:Level2})
MERGE (t) -[:Aggregates]->(t1)
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,t1,
SPLIT(Level3,';') AS value
UNWIND value AS result 
MATCH (ot:ObjectType)
WHERE ot.objectType = result 
MERGE (t1)-[:Aggregates]->(ot)
set ot:level3
MERGE (t1)-[:Aggregates]->(t2:Technology:level3{technologyName:Level3})
