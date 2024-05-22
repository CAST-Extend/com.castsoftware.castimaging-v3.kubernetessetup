MATCH(ot:ObjectType:`ApplicationName`)-[:Match]->(o:Object:`ApplicationName`)-[:References]->(o1:Object:`ApplicationName`)<-[:Match]-(ot1:ObjectType:`ApplicationName`)
MERGE(ot)-[:Call]->(ot1);

