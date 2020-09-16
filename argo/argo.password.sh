#!/bin/bash

## get pod name for password
OLDPASS=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
NEWPASS='VMware1!SDDC'
echo "Old Password [ $OLDPASS ] new password [ ${NEWPASS} ]"

## change password
argocd login 172.19.255.1 --insecure --username admin --password "${OLDPASS}"
argocd account update-password --account admin --current-password "${OLDPASS}" --new-password "${NEWPASS}"
