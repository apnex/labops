#!/bin/bash

NEWPASS=$1

read -r -d '' FILTER <<-'EOF'
	.items[] | .spec.containers[0] |
		{
			"name": .name,
			"resources": .resources
		}
EOF
kubectl -n sockshop get pods -o json | jq --tab "${FILTER}"
