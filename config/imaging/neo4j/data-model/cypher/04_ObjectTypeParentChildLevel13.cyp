LOAD CSV WITH HEADERS FROM 'file:///objtypeContainer.csv' AS row
WITH row.level6 AS Level1 ,row.level7 AS Level2 ,row.level8 AS Level3 ,row.level9 AS Level4 , row.level10 AS Level5,row.level11 AS Level6
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6
MATCH(ot:ObjectType:`ApplicationName`:level6) WHERE ot.objectType = Level1
MATCH(ot1:ObjectType:`ApplicationName`) WHERE ot1.objectType = Level2
MERGE(ot)-[:Aggregates]->(ot1) ON CREATE SET ot1:level7;

LOAD CSV WITH HEADERS FROM 'file:///objtypeContainer.csv' AS row
WITH row.level6 AS Level1 ,row.level7 AS Level2 ,row.level8 AS Level3 ,row.level9 AS Level4 , row.level10 AS Level5,row.level11 AS Level6
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6
MATCH(ot:ObjectType:`ApplicationName`:level7) WHERE ot.objectType = Level2
MATCH(ot1:ObjectType:`ApplicationName`) WHERE ot1.objectType = Level3
MERGE(ot)-[:Aggregates]->(ot1) ON CREATE SET ot1:level8;

LOAD CSV WITH HEADERS FROM 'file:///objtypeContainer.csv' AS row
WITH row.level6 AS Level1 ,row.level7 AS Level2 ,row.level8 AS Level3 ,row.level9 AS Level4 , row.level10 AS Level5,row.level11 AS Level6
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6
MATCH(ot:ObjectType:`ApplicationName`:level8) WHERE ot.objectType = Level3
MATCH(ot1:ObjectType:`ApplicationName`) WHERE ot1.objectType = Level4
MERGE(ot)-[:Aggregates]->(ot1) ON CREATE SET ot1:level9;

LOAD CSV WITH HEADERS FROM 'file:///objtypeContainer.csv' AS row
WITH row.level6 AS Level1 ,row.level7 AS Level2 ,row.level8 AS Level3 ,row.level9 AS Level4 , row.level10 AS Level5,row.level11 AS Level6
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6
MATCH(ot:ObjectType:`ApplicationName`:level9) WHERE ot.objectType = Level4
MATCH(ot1:ObjectType:`ApplicationName`) WHERE ot1.objectType = Level5
MERGE(ot)-[:Aggregates]->(ot1) ON CREATE SET ot1:level10;

LOAD CSV WITH HEADERS FROM 'file:///objtypeContainer.csv' AS row
WITH row.level6 AS Level1 ,row.level7 AS Level2 ,row.level8 AS Level3 ,row.level9 AS Level4 , row.level10 AS Level5,row.level11 AS Level6
WITH DISTINCT Level1,Level2,Level3,Level4,Level5,Level6
MATCH(ot:ObjectType:`ApplicationName`:level10) WHERE ot.objectType = Level5
MATCH(ot1:ObjectType:`ApplicationName`) WHERE ot1.objectType = Level6
MERGE(ot)-[:Aggregates]->(ot1) ON CREATE SET ot1:level11;