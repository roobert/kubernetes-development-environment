# `kdev` - A Kubernetes Development Environment

A profile based development environment within a cluster with persistent storage.

## Usage

```
# Install
mkdir -p "${HOME}/opt"
curl git@github.com:roobert/kubernetes-development-environment.git -o kdev.zip
unzip kdev.zip -d "${HOME}/opt"

# Add to path
export PATH="$PATH:$HOME/opt/kubernetes-development-environment/bin"

kdev help
```

## About

* **Customizable environment**
    * Simply create a shell script in a profile (`profile/<profile>/init.sh`) containing any commands to run to configure the pod
    * Optionally add any kubernetes manifests to configure the pod context to `profile/<profile>/manifests` - this can be used to do things like create a service account for the pod to run under
* **Profile based**
    * Create different profiles for different development environments
    * Share buckets across profiles or have unique buckets per profile
    * Override the default container image
* **Persistent Storage Bucket**
    * Avoid losing state when the connection drops by saving files to the optionally mounted bucket`/mnt/<profile-name>`
* **Tidy**
    * The `destroy` command(s) can be used to reset the state of the remote cluster once work has completed
* **Portable** - written in pure bash!
