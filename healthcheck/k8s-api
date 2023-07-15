#!/bin/bash

## check if account exists
#kubectl create serviceaccount labops-admin 2>/dev/null

SERVICE_ACCOUNT=labops-admin

# Get the ServiceAccount's token Secret's name
SECRET=$(kubectl get serviceaccount ${SERVICE_ACCOUNT} -o json | jq -Mr '.secrets[].name | select(contains("token"))')
echo "SECRET NAME: ${SECRET}"

# Extract the Bearer token from the Secret and decode
TOKEN=$(kubectl get secret ${SECRET} -o json | jq -Mr '.data.token' | base64 -d)
echo "TOKEN VALUE: ${TOKEN}"

# Extract, decode and write the ca.crt to a temporary location
kubectl get secret ${SECRET} -o json | jq -Mr '.data["ca.crt"]' | base64 -d > /tmp/ca.crt
echo "CA Cert"
cat /tmp/ca.crt

# Get the API Server location
#APISERVER=https://$(kubectl -n default get endpoints kubernetes --no-headers | awk '{ print $2 }')
APISERVER="localhost:6443"

echo "APISERVER: ${APISERVER}"

echo "CURL: openapi/v2"
curl -s ${APISERVER}/openapi/v2  --header "Authorization: Bearer ${TOKEN}" --cacert /tmp/ca.crt

echo "CURL: api/v1/namespaces/default/pods"
curl -vLs \
	--header "Authorization: Bearer ${TOKEN}" \
	--cacert /tmp/ca.crt \
https://${APISERVER}/api/v1/namespaces/default/pods
# | jq -rM '.items[].metadata.name'

echo "CURL: api/v1/namespaces/default/pods"
curl -vLs \
	--header "Authorization: Bearer ${TOKEN}" \
	--cacert /tmp/ca.crt \
https://${APISERVER}/api/v1/namespaces/kube-system/pods | jq -rM '.items[].metadata.name'
