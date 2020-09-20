#!/bin/bash

read -r -d '' FILTER <<-'EOF'
	.spec.template.spec.containers[0].resources = {
		"limits": {
			"cpu": "300m",
			"memory": "300Mi"
		},
		"requests": {
			"cpu": "100m",
			"memory": "100Mi"
		}
	}
EOF

kubectl -n sockshop get deployments orders -o json \
| jq --tab "${FILTER}" \
| kubectl replace -f -
