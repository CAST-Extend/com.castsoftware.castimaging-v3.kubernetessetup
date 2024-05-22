LOAD CSV WITH HEADERS FROM 'file:///objectTypeColors.csv' AS row
WITH row.object_type AS obj,row.color AS color
WITH obj, color
MATCH(o:Object:`ApplicationName`) WHERE o.objectType = obj
WITH distinct o, color
SET o.color = color;

LOAD CSV WITH HEADERS FROM 'file:///objectTypeColors.csv' AS row
WITH row.object_type AS obj,row.color AS color
WITH obj, color
MATCH(o:ObjectType:`ApplicationName`) WHERE o.objectType = obj
WITH distinct o, color
SET o.color = color;
