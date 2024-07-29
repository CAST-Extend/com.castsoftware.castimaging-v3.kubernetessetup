# Adding levels to technology nodes

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM 'file:///objectMappingLevels.csv' AS row FIELDTERMINATOR ';'
MATCH (t:Technology) WHERE t.technologyName = row.nodelabel
CALL apoc.create.addLabels( [t], ["level" + row.level]) yield node
return node