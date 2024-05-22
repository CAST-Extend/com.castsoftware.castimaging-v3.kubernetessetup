CREATE CONSTRAINT ON (n:ObjectType) ASSERT n.name IS UNIQUE;
CREATE CONSTRAINT ON (n:Technology) ASSERT n.name IS UNIQUE;

CREATE INDEX ON :Object(objectType);

CREATE INDEX ON :ObjectType(objectType);

// Wait indexes to be populated
CALL db.awaitIndexes(500);


