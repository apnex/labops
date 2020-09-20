#!/bin/bash

NAMESPACE=${1}
read -r -d '' EXTRACT <<-'EOF'
	. |
	{
		"apiVersion": .apiVersion,
		"kind": .kind,
		"metadata": (.metadata |
			if (length > 0) then
				.labels? | ({
					"labels": with_entries(select(.key == "app.kubernetes.io/name"))
				})
			else {} end
		),
		"spec": "test"
	}
EOF
#				.labels? | ({
#					"labels": with_entries(select(.key == "app.kubernetes.io/name"))
#				})
#		"metadata": (.metadata? |
#			.labels? | ({
#				"labels": with_entries(select(.key == "app.kubernetes.io/name"))
#			})
#		),

read -r -d '' NEWTEST <<-'EOF'
{
	"apiVersion": "apps/v1",
	"kind": "Deployment"
}
EOF

read -r -d '' NEXTRACT <<-'EOF'
{
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {
		"annotations": {},
		"labels": {
			"app.kubernetes.io/component": "redis",
			"app.kubernetes.io/name": "argocd-redis",
			"app.kubernetes.io/part-of": "argocd"
		},
		"name": "argocd-redis",
		"namespace": "argocd"
	}
}
EOF

echo "TEST1"
echo "${NEXTRACT}" | jq --tab "${EXTRACT}"
echo "TEST2"
#echo "${NEWTEST}" | jq --tab .
echo "${NEWTEST}" | jq --tab "${EXTRACT}"

#DEPLOYMENTS=$(kubectl -n "${NAMESPACE}" get deployments -o json)
#IFS=$'\n'
#for DEPA in $(echo "${DEPLOYMENTS}" | jq -c '.items[]'); do
#	NAME=$(echo "${DEPA}" | jq -r '.metadata.name')
#	mkdir -p "./output/${NAMESPACE}"
#	echo "${DEPA}" | jq --tab "${EXTRACT}" >"./output/${NAMESPACE}/${NAME}.yaml"
#done
