MATCH(t2)-[:Aggregates]->(t:level13:`ApplicationName`)-[r:Call]->(t1:level13)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level13:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level12:`ApplicationName`)-[r:Call]->(t1:level12)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level12:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level11:`ApplicationName`)-[r:Call]->(t1:level11)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level11:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level10:`ApplicationName`)-[r:Call]->(t1:level10)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level10:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level9:`ApplicationName`)-[r:Call]->(t1:level9)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level9:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level8:`ApplicationName`)-[r:Call]->(t1:level8)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level8:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level7:`ApplicationName`)-[r:Call]->(t1:level7)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level7:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level6:`ApplicationName`)-[r:Call]->(t1:level6)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level6:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level5:`ApplicationName`)-[r:Call]->(t1:level5)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level5:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level4:`ApplicationName`)-[r:Call]->(t1:level4)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level4:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level3:`ApplicationName`)-[r:Call]->(t1:level3)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level3:`ApplicationName`)-[r:Call]-(n)
DELETE r;

MATCH(t2)-[:Aggregates]->(t:level2:`ApplicationName`)-[r:Call]->(t1:level2)<-[r1:Aggregates]-(t3)
MERGE (t2)-[:Call]->(t3);

MATCH (n:level2:`ApplicationName`)-[r:Call]-(n)
DELETE r;

