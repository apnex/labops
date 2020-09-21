#!/bin/bash
curl -s http://10.30.0.63:81/api/planes?page=1 | jq --tab .
