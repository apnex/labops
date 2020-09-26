#!/bin/bash
## this enables the metric server to communicate to 0.0.0.0:4443

read -r -d '' FILTER <<-'EOF'
	.spec.template.spec.containers[0].args = [
		"--kubelet-preferred-address-types=InternalIP",
		"--kubelet-insecure-tls",
		"--cert-dir=/tmp",
		"--secure-port=4443"
	]
EOF

kubectl -n kube-system get deployments metrics-server -o json \
| jq --tab "${FILTER}" \
| kubectl replace -f -
