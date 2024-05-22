LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
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
set ot:level3;

####Level3 ------ Level4 

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level3  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
MATCH(t:Technology{technologyName:Level2})
MERGE (t1:Technology:level3{technologyName:Level3})
MERGE (t) -[:Aggregates]->(t1)
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,t1,
SPLIT(Level4,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
WITH *
MERGE (t1)-[:Aggregates]->(ot) ON CREATE SET 
ot:level4
WITH t1,
COUNT (DISTINCT ot) as count
SET t1.count = count;

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level3  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,
SPLIT(Level4,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
MATCH(ot1:ObjectType:level3)
MERGE(ot1)-[:Aggregates]->(ot) ON CREATE SET ot:level4;

#Level4 -------- Level5

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level4  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
MATCH(t:Technology{technologyName:Level3})
MERGE (t1:Technology:level4{technologyName:Level4})
MERGE (t) -[:Aggregates]->(t1)
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,t1,
SPLIT(Level5,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
WITH *
MERGE (t1)-[:Aggregates]->(ot) ON CREATE SET 
ot:level5
WITH t1,
COUNT (DISTINCT ot) AS count
SET t1.count = count;

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level3  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,
SPLIT(Level5,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
MATCH(ot1:ObjectType:level4)
MERGE(ot1)-[:Aggregates]->(ot) ON CREATE SET ot:level5;

#Level5 ----- Level6

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level5  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
MATCH(t:Technology{technologyName:Level4})
MERGE (t1:Technology:level5{technologyName:Level5})
MERGE (t) -[:Aggregates]->(t1)
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,t1,
SPLIT(Level6,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
WITH *
MERGE (t1)-[:Aggregates]->(ot) ON CREATE SET 
ot:level6
WITH t1,
COUNT (DISTINCT ot) AS count
SET t1.count = count;

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level3  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,
SPLIT(Level6,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
MATCH(ot1:ObjectType:level5)
MERGE(ot1)-[:Aggregates]->(ot) ON CREATE SET ot:level6;



#Level6 ----- Level7

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level6  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
MATCH(t:Technology{technologyName:Level5})
MERGE (t1:Technology:level6{technologyName:Level6})
MERGE (t) -[:Aggregates]->(t1)
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,t1,
SPLIT(Level7,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
WITH *
MERGE (t1)-[:Aggregates]->(ot) ON CREATE SET 
ot:level7
WITH t1,
COUNT (DISTINCT ot) AS count
SET t1.count = count;

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level3  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,
SPLIT(Level7,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
MATCH(ot1:ObjectType:level6)
MERGE(ot1)-[:Aggregates]->(ot) ON CREATE SET ot:level7;

#Level7 -------- Level8

LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level7  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
MATCH(t:Technology{technologyName:Level6})
MERGE (t1:Technology:level7{technologyName:Level7})
MERGE (t) -[:Aggregates]->(t1)
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,t1,
SPLIT(Level8,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
WITH *
MERGE (t1)-[:Aggregates]->(ot) ON CREATE SET 
ot:level8
WITH t1,
COUNT (DISTINCT ot) AS count
SET t1.count = count;


LOAD CSV WITH HEADERS FROM 'file:///TechnologyDrillDownWithoutTechnologyNodePrefix_832018.csv' AS row
WITH row.`Level 1` AS Level1 ,row.`Level 2` AS Level2 ,row.`Level 3` AS Level3 ,row.`Level 4` AS Level4 , row.`Level 5` AS Level5,row.`Level 6` AS Level6,row.`Level 7` AS Level7,row.`Level 8` AS Level8  WHERE NOT Level3  CONTAINS ';' AND NOT Level3 CONTAINS 'to ignore'
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6,Level7,Level8,
SPLIT(Level8,';') AS value
UNWIND value AS result
MATCH (ot:ObjectType)
WHERE ot.objectType = result
MATCH(ot1:ObjectType:level7)
MERGE(ot1)-[:Aggregates]->(ot) ON CREATE SET ot:level8;



##DELETE NODES NOT IN THE APPLICATION

MATCH(t:Technology:level1)-[:Aggregates]->(t2:Technology:level2)-[:Aggregates]->(t3:Technology:level3)
WHERE NOT EXISTS (t3.count)
WITH t3
MATCH(t3)-[:Aggregates]->(t4:Technology:level4)
WHERE NOT EXISTS (t4.count)
DETACH DELETE t3,t4;

MATCH(t1:Technology:level5)
WHERE not exists ((t1)-->())
DETACH DELETE t1;

MATCH(t1:Technology:level4)
WHERE not exists ((t1)-->())
DETACH DELETE t1;

MATCH(t1:Technology:level3)
WHERE not exists ((t1)-->())
DETACH DELETE t1;

MATCH(t1:Technology:level2)
WHERE not exists ((t1)-->())
DETACH DELETE t1;

MATCH(t1:Technology:level1)
WHERE not exists ((t1)-->())
DETACH DELETE t1;


### Links Between Nodes





