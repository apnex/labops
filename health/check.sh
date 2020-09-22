#!/bin/bash

echo "HEALTH"
curl -s http://10.30.0.63:81/api/healthcheck | jq --tab .

echo "PLANES"
curl -s http://10.30.0.63:81/api/planes

