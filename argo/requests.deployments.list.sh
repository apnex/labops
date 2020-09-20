#!/bin/bash
read -r -d '' FILTER <<-'EOF'
	.items[] | .spec.template.spec.containers[0] |
		{
			"name": .name,
			"resources": .resources
		}
EOF
read -r -d '' NEWFILTER <<-'EOF'
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
kubectl -n sockshop get deployments -o json | jq --tab "${FILTER}"
