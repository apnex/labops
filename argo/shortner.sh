#!/bin/bash

curl -i https://git.io \
	-F "url=https://raw.githubusercontent.com/apnex/labops/master/argo/app.index.yaml" \
	-F "code=app.index.yaml"
