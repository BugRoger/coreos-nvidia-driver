#!/bin/sh

set -x

cp -R /opt/nvidia /rootfs/opt
cp  /install.sh /rootfs/tmp/

chroot /rootfs /tmp/install.sh
