#Adding Adherence function in the model

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM 'file:///objectAdherenceMappings.csv' AS row FIELDTERMINATOR ';'
MERGE (a:Adherence {adherenceFullName: row.adherence, mappingName: row.nodelabel, exclusive: row.exclusive}) ON CREATE SET a.treeChild = 1 ON MATCH SET a.treeChild = coalesce(a.treeChild,0) + 1
MERGE (t:Technology {technologyName: row.nodelabel}) ON CREATE SET t.treeParent = 1 ON MATCH SET t.treeParent = coalesce(t.treeParent,0) + 1
WITH *
MATCH(t1:Technology {technologyName: row.nodelabel})
MATCH(a1:Adherence{adherenceFullName: row.adherence})
MERGE (t1)-[:Aggregates]->(a1)

