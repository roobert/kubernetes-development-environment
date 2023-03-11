#!/usr/bin/env bash
set -euo pipefail

# Install gcsfuse - required to mount a gcp bucket
apt update
apt -y install lsb-core
DISTRO_CODENAME="$(lsb_release -c -s)"
GCSFUSE_REPO="gcsfuse-${DISTRO_CODENAME}"
echo "deb https://packages.cloud.google.com/apt ${GCSFUSE_REPO} main" | tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt update
apt -y install gcsfuse

# install dev tools
apt -y install python-as-python3 python3-pip python3-venv
