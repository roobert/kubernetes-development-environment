#!/usr/bin/env bash

set -euo pipefail

USER=$(whoami)

set +u
PROFILE="${1}"
set -u

KDEV_NAME="kdev-${USER}-${PROFILE}"
KDEV_NAMESPACE="${KDEV_NAME}"

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

	profile_check
	profile_read

	# FIXME: warn about deleting data!
	set +u
	if [[ $2 == "destroy" ]]; then
		set -u
		bucket_iam_destroy
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

	pod_fast_connect_if_exists

	pre_hook
	bucket_create
	manifests_template
	manifests_apply
	bucket_iam_create
	pod_init
	bucket_mount
	pod_connect
}

function pod_fast_connect_if_exists() {
	echo
	echo "==> checking if pod exists"

	set +e
	POD_READY=$(kubectl get pods --namespace="${KDEV_NAME}" "${KDEV_NAME}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
	set -e

	if [[ "${POD_READY}" == true ]]; then
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

function profile_check() {
	if ! test -d "./profiles/${PROFILE}"; then
		echo "Error: profile not found: ./profiles/${PROFILE}"
		exit 1
	fi
}

function profile_read() {
	echo "==> reading profile config"
	source "./profiles/${PROFILE}/config.sh"
}

function bucket_create() {
	echo
	echo "==> creating bucket"

	set +u
	if [[ -z "${KDEV_BUCKET_TYPE}" ]]; then
		echo "KDEV_BUCKET_TYPE not set, skipping bucket creation"
		set -u
		return
	fi

	if [[ "${KDEV_BUCKET_TYPE}" == "aws" ]] || [[ "${KDEV_BUCKET_TYPE}" == "AWS" ]]; then
		echo "KDEV_BUCKET_TYPE: ${KDEV_BUCKET_TYPE} not yet supported"
		set -u
		return
	fi

	if [[ -z "${KDEV_BUCKET_LOCATION}" ]]; then
		echo "Error: KDEV_BUCKET_LOCATION not set in profile config: ./profiles/${PROFILE}/config.sh"
		exit 1
	fi

	if [[ -z "${KDEV_BUCKET_PROJECT}" ]]; then
		echo "Error: KDEV_BUCKET_PROJECT not set in profile config: ./profiles/${PROFILE}/config.sh"
		exit 1
	fi
	set -u

	# create a bucket to store our data in
	if ! gsutil ls -p "${KDEV_BUCKET_PROJECT}" "gs://${KDEV_NAME}" 2>/dev/null; then
		gsutil mb -p "${KDEV_BUCKET_PROJECT}" -c regional -l "${KDEV_BUCKET_LOCATION}" "gs://${KDEV_NAME}"
	else
		echo "bucket already exists.."
	fi
}

function bucket_iam_create() {
	echo
	echo "==> setting up bucket IAM"

	# FIXME: check if already exists
	gcloud iam service-accounts create "${KDEV_NAME}" \
		--project="${KDEV_BUCKET_PROJECT}"

	# FIXME: check if already exists
	gcloud projects add-iam-policy-binding "${KDEV_BUCKET_PROJECT}" \
		--project "${KDEV_BUCKET_PROJECT}" \
		--member "serviceAccount:${KDEV_NAME}@${KDEV_BUCKET_PROJECT}.iam.gserviceaccount.com" \
		--role "roles/storage.admin"

	# FIXME: check if already exists
	gcloud iam service-accounts add-iam-policy-binding \
		--project "${KDEV_BUCKET_PROJECT}" \
		"${KDEV_NAME}@${KDEV_BUCKET_PROJECT}.iam.gserviceaccount.com" \
		--role roles/iam.workloadIdentityUser \
		--member "serviceAccount:${KDEV_BUCKET_PROJECT}.svc.id.goog[${KDEV_NAMESPACE}/${KDEV_NAME}]"

	# FIXME: check if already exists
	kubectl annotate serviceaccount "${KDEV_NAME}" \
		--namespace "${KDEV_NAMESPACE}" \
		"iam.gke.io/gcp-service-account=${KDEV_NAME}@${KDEV_BUCKET_PROJECT}.iam.gserviceaccount.com"
}

function bucket_iam_destroy() {
	echo
	echo "==> destroying bucket IAM"

	set +e
	# FIXME: check state
	gcloud projects remove-iam-policy-binding \
		"${KDEV_BUCKET_PROJECT}" \
		--project="${KDEV_BUCKET_PROJECT}" \
		--member="serviceAccount:${KDEV_NAME}@${KDEV_BUCKET_PROJECT}.iam.gserviceaccount.com" \
		--role='roles/storage.admin'

	# FIXME: check if already exists
	gcloud iam service-accounts delete \
		"${KDEV_NAME}@${KDEV_BUCKET_PROJECT}.iam.gserviceaccount.com" \
		--project="${KDEV_BUCKET_PROJECT}" \
		--quiet
	set -e
}

function bucket_mount() {
	echo
	echo "==> mounting bucket"
	# FIXME:
	# * remove flag when this issue is fixed: https://github.com/GoogleCloudPlatform/gcsfuse/issues/985
	kubectl exec -it --namespace="${KDEV_NAME}" "${KDEV_NAME}" -- \
		/bin/bash -c "mkdir -p /mnt/${KDEV_NAME} && gcsfuse --enable-storage-client-library=false ${KDEV_NAME} /mnt/${KDEV_NAME}"
}

function bucket_destroy() {
	echo
	echo "==> deleting bucket"
	set +e
	gsutil rm -r "gs://${KDEV_NAME}"
	set -e
}

# update manifests with KDEV_NAME..
function manifests_template() {
	echo
	echo "==> templating manifests"
	mkdir -p "./tmp/${KDEV_NAME}"

	for manifest in ./profiles/"${PROFILE}"/manifests/*.yaml; do
		echo
		echo "templating: ${manifest}"
		FILENAME=$(basename "${manifest}")
		sed "s/KDEV_NAMESPACE/${KDEV_NAMESPACE}/g;s/KDEV_NAME/${KDEV_NAME}/g" "${manifest}" >"./tmp/${KDEV_NAME}/${FILENAME}"
	done
}

function manifests_apply() {
	echo
	echo "==> applying manifests"
	for manifest in "./tmp/${KDEV_NAME}"/*.yaml; do
		if [[ $(basename "${manifest}") = "*_pod.yaml" ]]; then
			continue
		fi
		echo
		echo "processing: ${manifest}"
		kubectl apply -f "${manifest}"
	done
}

function manifests_destroy() {
	echo
	echo "==> destroying manifests"

	mkdir -p "./tmp/${KDEV_NAME}"

	for manifest in ./profiles/"${PROFILE}"/manifests/*.yaml; do
		echo
		echo "templating: ${manifest}"
		FILENAME=$(basename "${manifest}")
		sed "s/KDEV_NAMESPACE/${KDEV_NAMESPACE}/g;s/KDEV_NAME/${KDEV_NAME}/g" "${manifest}" >"./tmp/${KDEV_NAME}/${FILENAME}"
	done

	for manifest in $(ls -r ./tmp/"${KDEV_NAME}"/*.yaml); do
		echo
		echo "processing: ${manifest}"
		set +e
		kubectl delete -f "${manifest}"
		set -e
	done
}

function pod_init() {
	echo
	echo "==> initialize pod"

	set +e
	POD_READY=$(kubectl get pods --namespace="${KDEV_NAME}" "${KDEV_NAME}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
	set -e

	# permit overriding default image
	KDEV_IMAGE="${KDEV_IMAGE:-ubuntu}"

	if [[ "${POD_READY}" != true ]]; then
		echo "Error: pod not ready"
		exit 1
	else
		if test -f "./profiles/${PROFILE}/init.sh"; then
			kubectl exec \
				-i \
				--namespace="${KDEV_NAME}" \
				"${KDEV_NAME}" \
				-- /bin/bash <./profiles/"${PROFILE}"/init.sh
		fi
	fi
}

function pod_connect() {
	echo
	echo "==> connecting to pod"

	KDEV_SHELL="${KDEV_SHELL:-/bin/bash}"

	kubectl exec -it --namespace="${KDEV_NAME}" "${KDEV_NAME}" -- "${KDEV_SHELL}"

	echo
	echo "==> disconnected from pod"
	echo
}

main "$@"
