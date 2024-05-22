#!/bin/bash

cp /var/lib/neo4j/config/configuration/apoc.conf /var/lib/neo4j/conf/
cp /var/lib/neo4j/config/configuration/neo4j.conf /var/lib/neo4j/conf/
cp /var/lib/neo4j/config/plugins/*.jar /var/lib/neo4j/plugins
unzip -nq /var/lib/neo4j/plugins/packagereference.zip -d /var/lib/neo4j/config/csv
ln -sf /var/lib/neo4j/config/csv /var/lib/neo4j/import
ln -sf /var/lib/neo4j/config/neo4j5_data /var/lib/neo4j
ln -sf /var/lib/neo4j/config/data-model /var/lib/neo4j

service ssh start
neo4j-admin dbms set-initial-password imaging
neo4j-admin database restore --verbose --from-path /var/lib/neo4j/config/csv/packagereference/packagereference*.backup packagereference --overwrite-destination
# neo4j-admin database migrate --verbose system
neo4j-admin server console
