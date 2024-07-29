#MergeMappings

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM 'file:///objectTypeMappings.csv' AS row FIELDTERMINATOR ';'
WITH row.objecttype as num, row.nodelabel as num1
MATCH (ot:ObjectType) WHERE  ot.objectType = num
WITH ot.objectType as objecttype,ot.defaultAipLanguage as nodelabel WHERE NOT nodelabel CONTAINS 'N/A'
WITH objecttype,nodelabel
MERGE (ot1:ObjectType {objectType:objecttype}) ON CREATE SET ot1.treeChild = coalesce(ot1.treeChild,0) + 1
MERGE (t1:Technology {technologyName:nodelabel}) ON CREATE SET t1.treeParent = coalesce(t1.treeParent,0) + 1
WITH *
MATCH(t2:Technology {technologyName: nodelabel})
MATCH(ot2:ObjectType{objectType: objecttype})
MERGE (t2)-[:Aggregates]->(ot2)