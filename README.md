# CoreOS Nvidia Installer

This image installs the Nvidia's drivers on CoreOS Container Linux. The
driver is a kernel module that is being compiled using the hosts exact kernel
sources.

CoreOS ships without compiler toolchain and without kernel sources. To make
matters worse updates will change the kernel unattended, requiring to recompile
the driver... :(

Two tricks are being used to solve this problem.

The image uses a multi-stage Docker build. In the first state a full CoreOS
developer image is being used to install the driver using the exact Kernel
sources and headers as the later host.

The second stage just copies the installation to a skinny Alpine image for
transport.

All this happens automatically for each CoreOS version using a TravisCI build.

Upon startup a systemd verifies the currently installed driver matches the
kernel. If not, this container is executed installing the proper precompiled
driver. Tadaaaa.

## Installation

```
docker run -v /:/rootfs --privileged bugroger/coreos-nvidia-installer:1409.5.0-381.22
```

This will install the Nvidia driver to `/opt/nvidia/381.22/1409.5.0`. Additionally,
a symlink to `/opt/nvidia/current` will be created.


## Kubernetes

The idea is that the shared libraries are mounted from the host system. This
avoids version mismatch between the hosts shared libraries and what was baked
into the container.

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






