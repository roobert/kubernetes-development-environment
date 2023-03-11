#!/usr/bin/env bash

set -euo pipefail

# * creating a bucket should be optional
# * support AWS buckets?
# * permit creating dev-env inside an existing namespace, or create a new one with
#   optional custom service account and permissions
# * targets should include: setup, connect, destroy

USER="rw"

set +u
PROFILE="${1}"
set -u

KDE_NAME="kde-${USER}-${PROFILE}"
NAMESPACE="${KDE_NAME}"

function main() {
	if [[ $# -eq 0 ]]; then
		echo "usage: $0 <profile> [command]"
		echo
		echo "profiles:"
		echo
		for profile in ./profiles/*; do
			echo "  $(basename "${profile}")"
		done
		echo
		echo "commands:"
		echo
		echo "  setup   - configure but don't connect"
		echo "  connect - setup (if required) and connect (default command if none specified)"
		echo "  destroy - destroy all resources relating to the profile, apart from data bucket"
		echo "  destroy-data - destroy the data bucket and all data!"
		echo
		exit 1
	fi

	# FIXME: warn about deleting data!
	set +u
	if [[ $2 == "destroy" ]]; then
		set -u
		echo "==> destroying resources"
		pod_destroy
		manifests_destroy
		exit
	fi
	set -u

	set +u
	if [[ $2 == "destroy-data" ]]; then
		set -u
		echo "==> destroying data"
		bucket_destroy
		exit
	fi
	set -u

	check_profile

	fast_connect_if_pod_exists

	read_profile_config
	pre_hook
	bucket_create
	manifests_template
	manifests_apply
	pod_create
	bucket_mount
	pod_connect
}

function fast_connect_if_pod_exists() {
	echo "==> checking if pod exists"

	set +e
	POD_READY=$(kubectl get pods --namespace="${KDE_NAME}" "${KDE_NAME}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
	set -e

	if [ "${POD_READY}" == "true" ]; then
		pod_connect
		exit
	fi
}

function pre_hook() {
	if test -f "./profiles/${PROFILE}/pre-hook.sh"; then
		echo "==> running pre-hook"
		./profiles/"${PROFILE}"/pre.sh
	fi
}

function check_profile() {
	if ! test -d "./profiles/${PROFILE}"; then
		echo "Error: profile not found: ./profiles/${PROFILE}"
		exit 1
	fi
}

function read_profile_config() {
	echo
	echo "==> reading profile config"
	source "./profiles/${PROFILE}/config.sh"
}

function bucket_create() {
	echo
	echo "==> creating bucket"

	set +u
	if [[ -z "${BUCKET_TYPE}" ]]; then
		echo "BUCKET_TYPE not set, skipping bucket creation"
		set -u
		return
	fi

	if [[ "${BUCKET_TYPE}" == "aws" ]] || [[ "${BUCKET_TYPE}" == "AWS" ]]; then
		echo "BUCKET_TYPE: ${BUCKET_TYPE} not yet supported"
		set -u
		return
	fi

	if [[ -z "${BUCKET_LOCATION}" ]]; then
		echo "Error: BUCKET_LOCATION not set in profile config: ./profiles/${PROFILE}/config.sh"
		exit 1
	fi

	if [[ -z "${BUCKET_PROJECT}" ]]; then
		echo "Error: BUCKET_PROJECT not set in profile config: ./profiles/${PROFILE}/config.sh"
		exit 1
	fi
	set -u

	# create a bucket to store our data in
	if ! gsutil ls -p "${BUCKET_PROJECT}" "gs://${KDE_NAME}" 2>/dev/null; then
		gsutil mb -p "${BUCKET_PROJECT}" -c regional -l "${BUCKET_LOCATION}" "gs://${KDE_NAME}"
	else
		echo "bucket already exists.."
	fi
}

function bucket_mount() {
	echo
	echo "==> mounting bucket"
	#kubectl exec -it --namespace="${KDE_NAME}" "${KDE_NAME}" -- \
	#	gcsfuse --implicit-dirs "${KDE_NAME}" "/mnt/${KDE_NAME}"
	kubectl exec -it --namespace="${KDE_NAME}" "${KDE_NAME}" -- \
		gcsfuse --implicit-dirs "${KDE_NAME}" "/mnt/${KDE_NAME}"
}

function bucket_destroy() {
	echo
	echo "==> deleting bucket"
	set +e
	gsutil rm -r "gs://${KDE_NAME}"
	set -e
}

# update manifests with KDE_NAME..
function manifests_template() {
	echo
	echo "==> templating manifests"
	mkdir -p "./tmp/${KDE_NAME}"

	for manifest in ./profiles/"${PROFILE}"/manifests/*.yaml; do
		echo
		echo "processing: ${manifest}"
		FILENAME=$(basename "${manifest}")
		sed "s/KDE_NAME/${KDE_NAME}/g;s/NAMESPACE/${NAMESPACE}/g" "${manifest}" >"./tmp/${KDE_NAME}/${FILENAME}"
	done
}

function manifests_apply() {
	echo
	echo "==> applying manifests"
	for manifest in "./tmp/${KDE_NAME}"/*.yaml; do
		echo
		echo "processing: ${manifest}"
		kubectl apply -f "${manifest}"
	done
}

function manifests_destroy() {
	echo
	echo "==> destroying manifests"

	mkdir -p "./tmp/${KDE_NAME}"

	for manifest in ./profiles/"${PROFILE}"/manifests/*.yaml; do
		echo
		echo "processing: ${manifest}"
		FILENAME=$(basename "${manifest}")
		sed "s/KDE_NAME/${KDE_NAME}/g;s/NAMESPACE/${NAMESPACE}/g" "${manifest}" >"./tmp/${KDE_NAME}/${FILENAME}"
	done

	for manifest in $(ls -r ./tmp/"${KDE_NAME}"/*.yaml); do
		echo
		echo "processing: ${manifest}"
		set +e
		kubectl delete -f "${manifest}"
		set -e
	done

	# echo "removing temporary files.."
	# rm -vrf "./tmp/${KDE_NAME}"
}

# create a container and run post-init shell if it doesn't already exist
function pod_create() {
	echo
	echo "==> creating pod"

	set +e
	POD_READY=$(kubectl get pods --namespace="${KDE_NAME}" "${KDE_NAME}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
	set -e

	# permit overriding the container image..
	KDEV_IMAGE=${KDEV_IMAGE:-"ubuntu"}

	if [ "${POD_READY}" != "true" ]; then
		if ! test -f "./profiles/${PROFILE}/init.sh"; then
			kubectl run \
				-i \
				--namespace="${KDE_NAME}" \
				--overrides='{ "spec": { "serviceAccount": "'"${KDE_NAME}"'" } }' \
				--image "${KDEV_IMAGE}" \
				"${KDE_NAME}" \
				-- /bin/bash
		else
			kubectl run \
				-i \
				--namespace="${KDE_NAME}" \
				--overrides='{ "spec": { "serviceAccount": "'"${KDE_NAME}"'" } }' \
				--image "${KDEV_IMAGE}" \
				"${KDE_NAME}" \
				-- /bin/bash <./profiles/${PROFILE}/init.sh
		fi
	else
		echo "pod already exists.."
	fi
}

function pod_connect() {
	echo
	echo "==> connecting to pod"

	# wait for pod to be ready otherwise errors can occur
	sleep 1

	kubectl exec -it --namespace="${KDE_NAME}" "${KDE_NAME}" -- /bin/bash

	echo
	echo "==> disconnected from pod"
	echo
}

function pod_destroy() {
	echo
	echo "==> destroying pod"
	set +e
	kubectl delete pod --namespace="${KDE_NAME}" "${KDE_NAME}"
	set -e
}

main "$@"
