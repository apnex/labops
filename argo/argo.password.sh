#!/bin/bash

NEWPASS=$1

read -r -d '' FILTER <<-'EOF'
	.status.loadBalancer.ingress[0].ip as $IP
	| $IP + ":" + (.spec.ports[0].port|tostring)
EOF
export ARGOCD_SERVER=$(kubectl -n argocd get services vip-argocd-server -o json | jq -r "${FILTER}")
if [[ -n $NEWPASS ]]; then
	OLDPASS=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
	echo "Old Password [ $OLDPASS ] new password [ ${NEWPASS} ]"

	## change password
	argocd login ${ARGOCD_SERVER} --insecure --username admin --password "${OLDPASS}"
	argocd account update-password --account admin --current-password "${OLDPASS}" --new-password "${NEWPASS}"
fi
