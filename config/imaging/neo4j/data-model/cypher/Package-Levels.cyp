## First Level

MATCH(t:ObjectType)
WHERE t.objectType CONTAINS 'Package'
WITH t
MATCH (o:Object)
WHERE NOT o.objectFullName CONTAINS '.'
WITH t,o
MATCH(t)-[r:Match]->(o)
RETURN *

