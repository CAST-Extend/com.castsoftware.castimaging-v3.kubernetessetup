#!/bin/bash

transformQuery() {
    query=$(cat $1)
    echo ${query//ApplicationName/$2}
}
