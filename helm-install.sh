#!/bin/bash
helm install castimaging-v3 --create-namespace --namespace castimaging-v3 --set version=3.5.5 .