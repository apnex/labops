#!/bin/bash
## adjust to get each app and directly pipe to replace

APPS=$(kubectl -n argocd get applications -o json)
IFS=$'\n'
for APP in $(echo "${APPS}" | jq -c '.items[]'); do
	NAME=$(echo "${APP}" | jq -r '.metadata.name')
	echo "${NAME}"
	echo "${APP}" | jq '.metadata.finalizers = []' | kubectl replace -f -
	kubectl -n argocd delete app "${NAME}"
done
kubectl delete ns argocd
