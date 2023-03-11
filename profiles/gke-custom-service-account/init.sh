#!/usr/bin/env bash
set -euo pipefail

apt-get update
apt-get -y install lsb-release curl lsb-core apt-transport-https ca-certificates curl

DISTRO_CODENAME="$(lsb_release -c -s)"
GCSFUSE_REPO="gcsfuse-${DISTRO_CODENAME}"

echo "deb https://packages.cloud.google.com/apt ${GCSFUSE_REPO} main" | tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

apt-get update
apt-get -y install gcsfuse google-cloud-sdk
