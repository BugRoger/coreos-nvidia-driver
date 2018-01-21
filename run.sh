#!/bin/sh

set -x

mkdir /rootfs/opt
cp -R /opt/nvidia /rootfs/opt
cp  /install.sh /rootfs/tmp/

chroot /rootfs /tmp/install.sh
