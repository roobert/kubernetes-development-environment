# kdev - The Kubernetes Development Environment

Ever wish you had a development environment within a cluster with persistent storage? Say hello to kdev!

## About

* Customizable environment
    * Simply create an `profile/<profile>/init.sh` containing any commands you'd like to configure your
      environment
    * Optionally add any kubernetes manifests to configure the pod context to `profile/<profile>/manifests` - this can be used to do things like create a service account for the pod to run under
* Profile based
    * Create different profiles for different development environments
    * Share buckets across profiles or have unique buckets per profile
    * Override the default container image
* Supports creating and mounting buckets for persistent storage
    * Avoid losing state when you lose connection! Save any state to `/mnt/<profile-name>` and continue you where you left off
* Clean-up after yourself
    * The destroy command(s) can be used to reset the state of your remote cluster once you've finished a task
