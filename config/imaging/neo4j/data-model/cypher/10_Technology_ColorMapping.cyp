LOAD CSV WITH HEADERS FROM 'file:///techColor.csv' AS row
WITH row.techno AS tech,row.color AS color
WITH tech, color
MATCH(t:Technology:`ApplicationName`) WHERE t.technologyName = tech
WITH distinct t, color
SET t.color = color;