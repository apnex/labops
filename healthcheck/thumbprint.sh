#!/bin/bash

function getThumbprint {
	local HOST="${1}"
	local PAYLOAD=$(echo -n | timeout 3 openssl s_client -connect "${HOST}" 2>/dev/null)
	local PRINT=$(echo "$PAYLOAD" | openssl x509 -noout -fingerprint -sha256)
	local REGEX='^(.*)=(([0-9A-Fa-f]{2}[:])+([0-9A-Fa-f]{2}))$'
	if [[ $PRINT =~ $REGEX ]]; then
		local TYPE=${BASH_REMATCH[1]}
		local CODE=${BASH_REMATCH[2]}
	fi
	printf "%s\n" "${CODE}" |  sed "s/\(.*\)/\L\1/g" | sed "s/://g"
}

SOCKET="localhost:8080"
PRINT=$(getThumbprint "${SOCKET}" thumbprint 2>/dev/null)
if [[ -n ${PRINT} ]]; then
	echo "${PRINT}"
else
	echo "No response from ${SOCKET}"
fi
