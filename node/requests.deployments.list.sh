#!/bin/bash

NAMESPACE=${1}
read -r -d '' EXTRACT <<-'EOF'
	.
	| del(.metadata.managedFields)
	| del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")
	| del(.metadata.annotations."deployment.kubernetes.io/revision")
	| del(.metadata.creationTimestamp)
	| del(.metadata.generation)
	| del(.metadata.labels."app.kubernetes.io/instance")
	| del(.metadata.resourceVersion)
	| del(.metadata.selfLink)
	| del(.metadata.uid)
	| del(.spec.progressDeadlineSeconds)
	| del(.spec.revisionHistoryLimit)
	| del(.spec.strategy)
	| del(.spec.template.metadata.creationTimestamp)
	| del(.spec.template.spec.containers[0].terminationMessagePath)
	| del(.spec.template.spec.containers[0].terminationMessagePolicy)
	| del(.spec.template.spec.schedulerName)
	| del(.spec.template.spec.securityContext)
	| del(.spec.template.spec.terminationGracePeriodSeconds)
	| del(.spec.template.spec.restartPolicy)
	| del(.status)
EOF

DEPLOYMENTS=$(kubectl -n "${NAMESPACE}" get deployments -o json)
IFS=$'\n'
for DEPA in $(echo "${DEPLOYMENTS}" | jq -c '.items[]'); do
	NAME=$(echo "${DEPA}" | jq -r '.metadata.name')
	mkdir -p "./output/${NAMESPACE}"
	echo "${DEPA}" | jq --tab "${EXTRACT}" >"./output/${NAMESPACE}/${NAME}.yaml"
done
