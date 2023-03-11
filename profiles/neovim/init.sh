#!/usr/bin/env bash
set -euo pipefail

# Install gcp-sdk and gcsfuse
apt-get update
apt-get -y install lsb-release curl lsb-core apt-transport-https ca-certificates \
	curl python-is-python3 python3-venv python3-pip

DISTRO_CODENAME="$(lsb_release -c -s)"
GCSFUSE_REPO="gcsfuse-${DISTRO_CODENAME}"

echo "deb https://packages.cloud.google.com/apt ${GCSFUSE_REPO} main" | tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

apt-get update
apt-get -y install gcsfuse google-cloud-sdk software-properties-common git

# Install Neovim
add-apt-repository -y ppa:neovim-ppa/unstable
apt-get update
apt-get -y install neovim unzip

cd /root

# Install Lunarvim and dependencies
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "${HOME}/.cargo/env"

bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh)

# Install my dotfiles
curl https://github.com/roobert/dotfiles/archive/refs/heads/master.zip -Lo master.zip
unzip master.zip
mv dotfiles-master/.* .
rm -rf dotfiles-master master.zip
