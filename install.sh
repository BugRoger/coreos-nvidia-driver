#!/bin/bash

set -o errexit
set -o pipefail
set -u

set -x
ROOT_OS_RELEASE="${ROOT_OS_RELEASE:-/root/etc/os-release}"
ROOT_MOUNT_DIR="${ROOT_MOUNT_DIR:-/root}"
NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-396.26}"
NVIDIA_DRIVER_COREOS_VERSION=${NVIDIA_DRIVER_COREOS_VERSION:-1800.5.0}
NVIDIA_INSTALL_DIR_HOST="/opt/nvidia/${NVIDIA_DRIVER_VERSION}/${NVIDIA_DRIVER_COREOS_VERSION}"
NVIDIA_INSTALL_DIR_CONTAINER="/opt/nvidia/${NVIDIA_DRIVER_VERSION}/${NVIDIA_DRIVER_COREOS_VERSION}"
NVIDIA_PRODUCT_TYPE="${NVIDIA_PRODUCT_TYPE:-geforce}"

RETCODE_SUCCESS=0
RETCODE_ERROR=1
RETRY_COUNT=${RETRY_COUNT:-5}

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
  info "Running on CoreOS ${VERSION}"
}

check_installation() {
  info "Checking host installation"

  if [[ ! -f "${ROOT_MOUNT_DIR}${NVIDIA_INSTALL_DIR_HOST}" ]]; then
    info "Driver is not installed on host"
    return ${RETCODE_ERROR}
  fi

  info "Driver installed and compatible!"
}

check_version() {
  info "Checking installer version"

  if [[ "${VERSION}" != "${NVIDIA_DRIVER_COREOS_VERSION}" ]]; then
    error "Version missmatch. This installer won't work on this OS."
    return ${RETCODE_ERROR}
  fi
  info "Installer compatible! NVIDIA ${NVIDIA_DRIVER_VERSION} (${NVIDIA_PRODUCT_TYPE}) compiled for CoreOS ${NVIDIA_DRIVER_COREOS_VERSION}"
}

install_driver() {
  info "Installing Driver on Host"

  mkdir -p "${ROOT_MOUNT_DIR}${NVIDIA_INSTALL_DIR_HOST}"
  pushd "${ROOT_MOUNT_DIR}${NVIDIA_INSTALL_DIR_HOST}"

  cp -R ${NVIDIA_INSTALL_DIR_CONTAINER}/* .

  popd
}

mount_driver_in_container() {
  info "Mounting Driver in Container"

  mkdir -p "${ROOT_MOUNT_DIR}${NVIDIA_INSTALL_DIR_HOST}"
  pushd "${ROOT_MOUNT_DIR}${NVIDIA_INSTALL_DIR_HOST}"

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

  mkdir -p "${ROOT_MOUNT_DIR}${NVIDIA_INSTALL_DIR_HOST}"
  pushd "${ROOT_MOUNT_DIR}${NVIDIA_INSTALL_DIR_HOST}"

  mkdir -p ${ROOT_MOUNT_DIR}/opt/bin
  mount -t overlay -o lowerdir=${ROOT_MOUNT_DIR}/opt/bin,upperdir=bin,workdir=bin-workdir none ${ROOT_MOUNT_DIR}/opt/bin
  mount -t overlay -o lowerdir=${ROOT_MOUNT_DIR}/usr/lib64,upperdir=lib64,workdir=lib64-workdir none ${ROOT_MOUNT_DIR}/usr/lib64

  popd
}

update_container_ld_cache() {
  info "Updating container's ld cache"
  echo "${NVIDIA_INSTALL_DIR_CONTAINER}/lib64" > /etc/ld.so.conf.d/nvidia.conf
  ldconfig
}

load_driver_in_container() {
  info "Loading Driver"
  if ! lsmod | grep -q -w 'nvidia'; then
    insmod "${NVIDIA_INSTALL_DIR_CONTAINER}/lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia/nvidia.ko"
  fi
  if ! lsmod | grep -q -w 'nvidia_uvm'; then
    insmod "${NVIDIA_INSTALL_DIR_CONTAINER}/lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia/nvidia-uvm.ko"
  fi
  if ! lsmod | grep -q -w 'nvidia_drm'; then
    insmod "${NVIDIA_INSTALL_DIR_CONTAINER}/lib64/modules/"$(uname -r)"/kernel/drivers/video/nvidia/nvidia-drm.ko"
  fi
}

verify_nvidia_installation() {
  info "Verifying Nvidia installation"
  export PATH="${NVIDIA_INSTALL_DIR_CONTAINER}/bin:${PATH}"
  nvidia-smi
  nvidia-modprobe -c0 -u
}

main() {
  load_etc_os_release
  if ! check_installation; then
    check_version
    install_driver
  fi
  mount_driver_in_container
  update_container_ld_cache
  load_driver_in_container
  verify_nvidia_installation
  mount_driver_on_host
}

main "$@"

