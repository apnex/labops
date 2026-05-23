#!/bin/bash
## build.sh — trigger an in-cluster Kaniko build of a Dockerfile in a Git repo,
## pushing the resulting image to the in-cluster registry at 192.168.1.250:5000.
##
## Usage:
##   ./build.sh <github-org/repo> <ref> <context-subdir> <image-name> [<dockerfile>] [<tag>]
##
## Examples:
##   ./build.sh apnex/hermes main image hermes
##     -> builds image/Dockerfile in apnex/hermes@main
##     -> 192.168.1.250:5000/hermes:<short-sha>
##
##   ./build.sh apnex/hermes main image hermes Dockerfile v1.2.3
##     -> 192.168.1.250:5000/hermes:v1.2.3
##
## Env overrides:
##   REGISTRY   default: 192.168.1.250:5000
##   NAMESPACE  default: kaniko
set -euo pipefail

REPO="${1:?usage: $0 <github-org/repo> <ref> <context-subdir> <image-name> [dockerfile] [tag]}"
REF="${2:?ref required}"
CONTEXT_SUBDIR="${3:?context subdir required (use '.' for repo root)}"
IMAGE_NAME="${4:?image name required}"
DOCKERFILE="${5:-Dockerfile}"
TAG="${6:-}"

REGISTRY="${REGISTRY:-192.168.1.250:5000}"
NAMESPACE="${NAMESPACE:-kaniko}"

# Derive tag from short-SHA of the remote ref if not provided
if [[ -z "${TAG}" ]]; then
	SHA=$(git ls-remote "https://github.com/${REPO}" "${REF}" | awk '{print $1}' | head -c 7)
	if [[ -z "${SHA}" ]]; then
		echo "Error: couldn't resolve ${REPO}@${REF} to a SHA — bad repo or ref?" >&2
		exit 1
	fi
	TAG="${SHA}"
fi

DESTINATION="${REGISTRY}/${IMAGE_NAME}:${TAG}"
SAFE_TAG="${TAG//[^a-zA-Z0-9-]/-}"  # k8s job names: alphanumerics + hyphens only
JOB_NAME="${IMAGE_NAME}-build-${SAFE_TAG:0:24}-$(date +%s | tail -c 6)"

cat <<INFO
==> repo:         github.com/${REPO}
==> ref:          ${REF}
==> context:      ${CONTEXT_SUBDIR}
==> dockerfile:   ${DOCKERFILE}
==> destination:  ${DESTINATION}
==> job name:     ${JOB_NAME}
INFO

cd "$(dirname "$0")"

## Ensure kaniko namespace exists (idempotent)
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

## Substitute placeholders and create the Job
sed \
	-e "s|@JOB_NAME@|${JOB_NAME}|g" \
	-e "s|@REPO_URL@|github.com/${REPO}.git|g" \
	-e "s|@REVISION@|${REF}|g" \
	-e "s|@CONTEXT_SUBDIR@|${CONTEXT_SUBDIR}|g" \
	-e "s|@DOCKERFILE@|${DOCKERFILE}|g" \
	-e "s|@DESTINATION@|${DESTINATION}|g" \
	buildjob.yaml.tpl | kubectl apply -f -

echo
echo "==> waiting for pod to start..."
for _ in $(seq 1 30); do
	POD=$(kubectl -n "${NAMESPACE}" get pod -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
	[[ -n "${POD}" ]] && break
	sleep 1
done
if [[ -z "${POD:-}" ]]; then
	echo "Error: pod for ${JOB_NAME} didn't appear within 30s" >&2
	exit 1
fi
echo "==> pod: ${POD}"
echo "==> streaming build log:"
echo

kubectl -n "${NAMESPACE}" logs -f "${POD}" || true

echo
if kubectl -n "${NAMESPACE}" wait --for=condition=complete --timeout=30s "job/${JOB_NAME}" >/dev/null 2>&1; then
	echo "==> ✓ build complete: ${DESTINATION}"
	exit 0
elif kubectl -n "${NAMESPACE}" wait --for=condition=failed --timeout=5s "job/${JOB_NAME}" >/dev/null 2>&1; then
	echo "==> ✗ build failed"
	exit 1
else
	echo "==> build state unclear; inspect with: kubectl -n ${NAMESPACE} describe job/${JOB_NAME}"
	exit 2
fi
