#!/bin/bash

set -e

execute() {
    apps=$1
    appName=""
    for app in "${apps[@]}"
    do
        appName="${appName} ${app}"
    done
    appName=$(echo $appName)
    echo "Running $2 for $appName..."
    query=$(cat $2)
    local res="${query//ApplicationName/$appName}"
    echo $res | /var/lib/neo4j/bin/cypher-shell -u neo4j -p imaging --format verbose
    echo "Completed $2 for $appName..."
}

declare -a apps
for app in "$@"; do
    apps+=($app)
done

declare -a files=(00_indexes.cyp deletePrefix.cyp 01_TechnologyNodesMappingLevel2.cyp 02_TechnologyNodesMappingLevel7.cyp 03_TechnologyObjectTypeParentLink.cyp 04_ObjectTypeParentChildLevel13.cyp 05_DeleteUnusedNodes.cyp 06_LinkNodes.cyp 07_TechnologyLinks.cyp 09_Count_Technology.cyp 10_Technology_ColorMapping.cyp 11_Object_ColorMapping.cyp TransactionTechnology.cyp TransactionTechnology-contains-Object.cyp TransactionTechnology-References-TransactionTechnology.cyp transactionStatus.cyp startPoint_path.cyp endPoint_path.cyp object-count.cyp)

for file in "${files[@]}";do
    echo
      echo "*********************************************************************************************************"
      echo "PROCESSING file"
      echo "*********************************************************************************************************"
      content=$(cat cypher/$file)
      if [[ $content = *"ApplicationName"* ]]; then
        echo "Running $file for $@!"
        execute $apps cypher/$file
      else
        echo $file
        bash /var/lib/neo4j/bin/cypher-shell -u neo4j -p imaging --fail-fast --format verbose < cypher/$file
      fi
done
