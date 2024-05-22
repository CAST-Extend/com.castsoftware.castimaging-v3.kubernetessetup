MATCH (ot:ObjectType:`AppicationName`)
WITH ot, size((ot)-[:Match]->(:Object)) AS count
SET ot.count=count;

MATCH (t:Technology:`ApplicationName`) WITH t
  MATCH (t)<-[:Aggregates]-(ot:ObjectType)
  WITH t, sum(ot.count) AS count
    SET t.count = count;

 MATCH(t:Technology:`ApplicationName`) WITH t
 WITH t , size((t)-[:Aggregates]->(:Technology:`ApplicationName`)) AS count
 SET t.count = count;

 MATCH (t:Technology:`ApplicationName`) WITH t
  MATCH (t)-[:Aggregates]->(ot:ObjectType)
  WITH t, sum(ot.count) AS count
    SET t.count = count;

// TODO ADD the other count on the tree
