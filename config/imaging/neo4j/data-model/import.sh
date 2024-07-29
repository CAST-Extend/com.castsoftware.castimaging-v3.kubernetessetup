#!/bin/bash
set -e
NEO4J_PATH=/var/lib/neo4j

echo
echo "*********************************************************************************************************"
echo "Shutdown Neo4j"
echo "*********************************************************************************************************"
bash $NEO4J_PATH/bin/neo4j stop

echo
echo "*********************************************************************************************************"
echo "Delete Neo4j graph.db folder"
echo "*********************************************************************************************************"
rm -rf /var/lib/neo4j/data/*

ls /import

declare -a nodes=(objects.csv objectType.csv transactions.csv)
declare -a relationships=(belongsTo.csv objectTypeLinks.csv references.csv transactionObjects.csv startPoint.csv endPoint.csv)
declare -a apps

for node in "${nodes[@]}";do
    for file in /import/*/;do
        apps+=("--nodes $file$node")
    done
done

for relationship in "${relationships[@]}";do
    for file in /import/*/;do
        apps+=("--relationships $file$relationship")
    done
done

echo
echo "*********************************************************************************************************"
echo "Neo4j Import"
echo "*********************************************************************************************************"
$NEO4J_PATH/bin/neo4j-admin import \
	 --multiline-fields=true		\
     --ignore-duplicate-nodes=true \
     -ignore-missing-nodes=true \
     ${apps[*]}
echo
echo "*********************************************************************************************************"
echo "Startup Neo4j"
echo "*********************************************************************************************************"
bash $NEO4J_PATH/bin/neo4j start

