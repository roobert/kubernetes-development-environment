# `kdev` - A Kubernetes Development Environment

A profile based development environment within a cluster with persistent storage.


## Install
```
# Install
mkdir -p "${HOME}/opt"
curl git@github.com:roobert/kubernetes-development-environment.git -o kdev.zip
unzip kdev.zip -d "${HOME}/opt"

# Add to path
export PATH="$PATH:$HOME/opt/kubernetes-development-environment/bin"

kdev help
```

## Usage

1. Make a copy of one of the existing profiles
2. Edit the `init.sh` script to run the post-boot commands
3. Edit the manifests in the `manifests` directory to configure any resources required
   for the pod - this could include services accounts, role bindings, etc.
4. Edit `config.sh` and configure the environment variables

Note that due to the ephemeral and immutable nature of containers, if a pod is restarted for any reason (node
upgrade, etc.) then the filesystem will be reset and all changes lost, including changes
made by `init.sh`. For this reason the examples configure the pods with a `restartPolicy` of `never` to act as a signal
that a pod is no-longer configured.

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
