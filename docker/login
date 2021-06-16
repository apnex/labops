#!/bin/bash
IFS=$'\n'

### tech references
#https://medium.com/titansoft-engineering/kubernetes-cluster-wide-access-to-private-container-registry-with-imagepullsecret-patcher-b8b8fb79f7e5
#https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/#registry-secret-existing-credentials

## login interactively
docker login

## perform kubectl healthcheck
## perform a check if config.json exists

## patch the [default] account for current namespace to use docker creds
function patchServiceAccount {
	local NAME="${1}"
	echo "Create new secret [ docker-login ] on namespace [ ${NAME} ]"
	kubectl create secret generic docker-login \
		--from-file=.dockerconfigjson=/root/.docker/config.json \
		--type=kubernetes.io/dockerconfigjson \
	-n "${NAME}"
	echo "Updated serviceaccount [ default ] for namespace [ ${NAME} ] to use [ docker-login ]"
	kubectl patch serviceaccount default \
		-p '{
			"imagePullSecrets": [
				{
					"name": "docker-login"
				}
			]
		}' \
	-n "${NAME}"
}

## delete pods with imagePull error in current namespace
function deleteErroredPods {
	local NAME="${1}"
	read -r -d '' JQSPEC <<-CONFIG
		.items[]
			| select(.status.containerStatuses[0].state.waiting.reason != null)
			| select(
				.status.containerStatuses[0].state.waiting.reason
				| contains("ImagePull")
			)
		| .metadata.name
	CONFIG
	PODS=$(kubectl -n "${NAME}" get pods -o json | jq -r "$JQSPEC")
	for POD in $(echo "${PODS}"); do
		echo "Delete [ ${POD} ]"
		kubectl -n "${NAME}" delete pod "${POD}"
	done
}

## loop over namespaces
NAMESPACES=$(kubectl get ns --output=json)
for NS in $(echo "${NAMESPACES}" | jq -c '.items[]'); do
	NAME=$(echo "${NS}" | jq -r '.metadata.name')
	echo "Checking namespace [ ${NAME} ]"
	patchServiceAccount "${NAME}"
	deleteErroredPods "${NAME}"
done
