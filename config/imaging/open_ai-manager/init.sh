#!/usr/bin/bash

cp  /opt/imaging/open_ai-manager/config/app.config /opt/imaging/open_ai-manager/

python /opt/imaging/open_ai-manager/server.py "/opt/imaging/open_ai-manager/app.config"