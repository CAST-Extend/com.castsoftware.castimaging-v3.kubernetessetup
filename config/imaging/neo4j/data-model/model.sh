#!/bin/bash
set -e

base=/var/lib/neo4j/data-model
cd $base

for app in /import/*/;do

    # Convert all csvs to unix format, CSVs generated on windows have carriage return which will prevents reading of app
    # names correctly
    cd $app
    dos2unix *.csv
    cd $base

    name="$(head -n 2 "$app/objects.csv" | tail -1 | cut -d';' -f 2) "
    ./exec.sh $name
done

echo "Data modeling completed!"