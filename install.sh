#!/bin/bash

set -o errexit
set -o pipefail
set -u

RETCODE_SUCCESS=0
RETCODE_ERROR=1
RETRY_COUNT=${RETRY_COUNT:-5}

set -x
ROOT_OS_RELEASE="${ROOT_OS_RELEASE:-/root/etc/os-release}"
ROOT_MOUNT_DIR="${ROOT_MOUNT_DIR:-/root}"

NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-396.26}"
NVIDIA_DRIVER_COREOS_VERSION=${NVIDIA_DRIVER_COREOS_VERSION:-1800.5.0}
NVIDIA_PRODUCT_TYPE="${NVIDIA_PRODUCT_TYPE:-geforce}"

if [[ ! -f "${ROOT_OS_RELEASE}" ]]; then
  error "File ${ROOT_OS_RELEASE} not found, /etc/os-release must be mounted into this container."
  exit ${RETCODE_ERROR}
fi
. "${ROOT_OS_RELEASE}"

ROOT_INSTALL_DIR_CURRENT="${ROOT_MOUNT_DIR}/opt/nvidia/${NVIDIA_DRIVER_VERSION}/${VERSION}"
ROOT_INSTALL_DIR="${ROOT_MOUNT_DIR}/opt/nvidia/${NVIDIA_DRIVER_VERSION}/${NVIDIA_DRIVER_COREOS_VERSION}"
CONTAINER_INSTALL_DIR="/opt/nvidia/${NVIDIA_DRIVER_VERSION}/${NVIDIA_DRIVER_COREOS_VERSION}"

_log() {
  local -r prefix="$1"
  shift
  echo "[${prefix}$(date -u "+%Y-%m-%d %H:%M:%S %Z")] ""$*" >&2
}

info() {
  _log "INFO    " "$*"
}

warn() {
  _log "WARNING " "$*"
}

error() {
  _log "ERROR   " "$*"
}

load_etc_os_release() {
  if [[ ! -f "${ROOT_OS_RELEASE}" ]]; then
    error "File ${ROOT_OS_RELEASE} not found, /etc/os-release must be mounted into this container."
    exit ${RETCODE_ERROR}
  fi
  . "${ROOT_OS_RELEASE}"

  ROOT_DRIVER_VERSION=${NVIDIA_DRIVER_VERSION}
  ROOT_DRIVER_COREOS_VERSION=${VERSION}
  ROOT_INSTALL_DIR_CURRENT="${ROOT_MOUNT_DIR}/opt/nvidia/${ROOT_DRIVER_VERSION}/${ROOT_DRIVER_COREOS_VERSION}"

  info "Running on CoreOS ${VERSION}"
}

check_installation() {
  info "Checking host installation"

  if [[ ! -d "${ROOT_INSTALL_DIR}" ]]; then
    info "Driver is not installed on host"
    return ${RETCODE_ERROR}
  fi

  info "Driver installed and compatible!"
}

install_driver() {
  info "Installing Driver on Host"

  mkdir -p "${ROOT_INSTALL_DIR}"
  pushd "${ROOT_INSTALL_DIR}"

  cp -R ${CONTAINER_INSTALL_DIR}/* .

  popd
}

check_version() {
  info "Checking installer version"

  if [[ ! -d "${ROOT_INSTALL_DIR_CURRENT}" ]]; then
    error "No matching driver found on host. Aborting."
    return ${RETCODE_ERROR}
  fi
  info "Driver compatible! NVIDIA ${ROOT_DRIVER_VERSION} (${NVIDIA_PRODUCT_TYPE}) compiled for CoreOS ${ROOT_DRIVER_COREOS_VERSION}"
}

mount_driver_in_container() {
  info "Mounting Driver in Container"

  mkdir -p "${ROOT_INSTALL_DIR_CURRENT}"
  pushd "${ROOT_INSTALL_DIR_CURRENT}"

  mkdir -p bin-workdir
  mount -t overlay -o lowerdir=/usr/bin,upperdir=bin,workdir=bin-workdir none /usr/bin

  mkdir -p lib64-workdir
  mount -t overlay -o lowerdir=/usr/lib/x86_64-linux-gnu,upperdir=lib64,workdir=lib64-workdir none /usr/lib/x86_64-linux-gnu

  mkdir -p drivers-workdir
  mkdir -p /lib/modules/"$(uname -r)"/video
  mount -t overlay -o lowerdir=/lib/modules/"$(uname -r)"/video,upperdir=lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia,workdir=drivers-workdir none /lib/modules/"$(uname -r)"/video

  trap "{ umount /lib/modules/\"$(uname -r)\"/video ; umount /usr/lib/x86_64-linux-gnu ; umount /usr/bin; }" EXIT
  popd
}

mount_driver_on_host() {
  info "Mounting Driver on Host"

  mkdir -p "${ROOT_INSTALL_DIR_CURRENT}"
  pushd "${ROOT_INSTALL_DIR_CURRENT}"

  mkdir -p ${ROOT_MOUNT_DIR}/opt/bin
  
  if ! findmnt /opt/bin; then 
    mount -t overlay -o lowerdir=${ROOT_MOUNT_DIR}/opt/bin,upperdir=bin,workdir=bin-workdir none ${ROOT_MOUNT_DIR}/opt/bin
  fi
  if ! findmnt /usr/lib64; then
    mount -t overlay -o lowerdir=${ROOT_MOUNT_DIR}/usr/lib64,upperdir=lib64,workdir=lib64-workdir none ${ROOT_MOUNT_DIR}/usr/lib64
  fi
  
  popd
}

update_container_ld_cache() {
  info "Updating container's ld cache"
  echo "${ROOT_INSTALL_DIR_CURRENT}/lib64" > /etc/ld.so.conf.d/nvidia.conf
  ldconfig
}

load_driver_in_container() {
  info "Loading Driver"
  if ! lsmod | grep -q -w 'nvidia'; then
    insmod "${ROOT_INSTALL_DIR_CURRENT}/lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia/nvidia.ko"
  fi
  if ! lsmod | grep -q -w 'nvidia_uvm'; then
    insmod "${ROOT_INSTALL_DIR_CURRENT}/lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia/nvidia-uvm.ko"
  fi
  if ! lsmod | grep -q -w 'nvidia_drm'; then
    insmod "${ROOT_INSTALL_DIR_CURRENT}/lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia/nvidia-drm.ko"
  fi
  if ! lsmod | grep -q -w 'nvidia_modeset'; then
    insmod "${ROOT_INSTALL_DIR_CURRENT}/lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia/nvidia-modeset.ko"
  fi
}

verify_nvidia_installation() {
  info "Verifying Nvidia installation"
  export PATH="${ROOT_INSTALL_DIR_CURRENT}/bin:${PATH}"
  nvidia-smi
  nvidia-modprobe -u -m -c 0
}

main() {
  load_etc_os_release
  if ! check_installation; then
    install_driver
  fi
  check_version
  mount_driver_in_container
  update_container_ld_cache
  load_driver_in_container
  verify_nvidia_installation
  mount_driver_on_host
}

main "$@"

