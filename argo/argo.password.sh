#!/bin/bash

NEWPASS=$1

if [[ -n $NEWPASS ]]; then
	OLDPASS=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
	echo "Old Password [ $OLDPASS ] new password [ ${NEWPASS} ]"

	## change password
	argocd login 172.19.255.1 --insecure --username admin --password "${OLDPASS}"
	argocd account update-password --account admin --current-password "${OLDPASS}" --new-password "${NEWPASS}"
fi
