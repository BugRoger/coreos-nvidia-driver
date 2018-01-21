# CoreOS Container Linux Nvidia Driver

[![Build Status](https://travis-ci.org/BugRoger/coreos-nvidia-driver.svg?branch=master)](https://travis-ci.org/BugRoger/coreos-nvidia-driver)


This image installs the Nvidia's drivers on CoreOS Container Linux. The
driver is a kernel module that is being compiled using the hosts' exact kernel
sources.

CoreOS ships without compiler toolchain and without kernel sources. To make
matters worse updates will change the kernel unattended, requiring to recompile
the driver... :(

Two tricks are being used to solve this problem.

The image uses a multi-stage Docker build. In the first state a full CoreOS
developer image is being used to install the driver using the exact Kernel
sources and headers as the later host. See: https://github.com/BugRoger/coreos-developer-docker

The second stage just copies the installation to a skinny Alpine image for
transport.

All this happens automatically for each CoreOS version using a TravisCI build.

Upon startup a systemd verifies the currently installed driver matches the
kernel. If not, this container is executed installing the proper precompiled
driver. Tadaaaa.

## Installation

Find the image on Docker Hub: https://hub.docker.com/r/bugroger/coreos-nvidia-driver

```
docker run -v /:/rootfs --privileged bugroger/coreos-nvidia-installer:1576.5.0-384.111
```

This will install the Nvidia driver to `/opt/nvidia/384.111/1576.5.0`. Additionally,
a symlink to `/opt/nvidia/current` will be created.

Instead of reconfiguring the `LD_LIBRARY_PATH` and `ldconf` cache locations,
the installer creates an overlay filesystem to mount the driver from
`/opt/nvidia` to `/usr/lib64` where kernel modules are expected. This makes the
system look like a regular installation.

The installer creates a `nvidia` service, that creates the shared library
cache, loads the kernel modules and starts the driver. It is bundles to the
`nvidia-perstience` service that also starts the persistence daemon.

## Auto-Update

In order to deal with unattended Container Linux updates this installer provides an 
automatic update mechanism. This is necessary due to frequent kernel updates. The
driver must have been built with exactly the same kernel version and sources.

In constrast to other installers, that run the whole compilation during each
boot, we here just check for a prebuilt Docker image. The image is being built
out-of-band by Travis for each update on all Container Linux release channels.

Once the host updates and reboots the `nvidia-update` service is started. It
will pull the exact kernel/driver combination and repeat the installation.

## Kubernetes Kubelet

As of this writing the Kubernetes Kubelet only enumerates (GPU) resources
during startup. That means the nvidia kernel module must have been loaded
before the Kubelet is started.

Using systemd a dependency to the `nvidia` service can be used:

```
[Unit]
After=nvidia.service
Requires=nvidia.service

[Service]
ExecStart=/opt/bin/kubelet ...
 
```

## Kubernetes 

Using the Nvidia drivers in Kubernetes posses two problems:

  1. Applications usually need to load the exact same shared libraries as
     installed on the host OS. 
  2. The Cuda libraries are ridiciously big ~2GB

Building new containers whenever the kernel or driver is updated, doing so
during and unattened upgrade, transporting them and on the same time patching
the Kubernetes specs is a major problem.

As a workaround, the idea is that the shared libraries are mounted from the
host system. This avoids version mismatch between the hosts' shared libraries
and what was baked into the container.

A spec using this installer looks like this:

```
apiVersion: apps/v1beta1 
kind: Deployment

metadata:
  name: nvidia-settings 
spec:
  replicas: 1 
  strategy: 
    type: Recreate
  template:
    metadata:
      labels:
        app: nvidia-settings
    spec:
      containers:
        - name: nvidia-settings 
          securityContext:
            privileged: true
          image: bugroger/x11:381.22
          imagePullPolicy: Always
          volumeMounts:
            - mountPath: /usr/local/nvidia
              name: nvidia 
            - mountPath: /usr/local/cuda
              name: cuda 
      volumes:
        - name: nvidia
          hostPath:
            path: /opt/nvidia/current
        - name: cuda
          hostPath:
            path: /opt/cuda/current
```

Note the `hostPath` value pointing to `current`. This makes the spec
independant of a specific driver version. Though if required, this can also be
used to pin to a specific version.

## Docker

Unfortunately, the Docker images are not completly unoblivious of this method.
The problem is that the `LD_LIBRARY_PATH` must be set, so that library can be
found.

By convention the Nvidia driver and Cuda libs are expected in `/usr/local/cuda`
and `/usr/local/nvidia`.

This can be prebaked into containers that want to use the mounted libs.

```
RUN echo "/usr/local/cuda/lib64" >> /etc/ld.so.conf.d/cuda.conf 
RUN echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf

ENV PATH $PATH:/usr/local/nvidia/bin:/usr/local/cuda/bin
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/local/nvidia/lib64/:/usr/local/cuda/lib64/
```






