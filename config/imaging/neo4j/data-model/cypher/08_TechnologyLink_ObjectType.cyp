USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM 'file:///objectTypeMappings.csv' AS row FIELDTERMINATOR ';'
  MATCH (t:Technology { technologyName: row.nodelabel})
  MATCH (o:ObjectType { objectType: row.objecttype})
  MERGE (o)-[:ContributeTo]->(t);
