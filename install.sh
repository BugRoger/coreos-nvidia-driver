#!/bin/sh

set -ev

mkdir -p /opt/nvidia/.work
mkdir -p /opt/bin
ln -fs /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/bin/* /opt/bin
ln -fs /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION /opt/nvidia/current
ln -fs /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/lib64/libnvidia-ml.so.$DRIVER_VERSION /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/lib64/libnvidia-ml.so
chmod u+s /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/bin/nvidia-modprobe

cat <<EOF > /etc/systemd/system/nvidia-update.service
[Unit]
After=docker.service
Requires=docker.service
Description=NVIDIA Update Driver

[Service]
EnvironmentFile=/etc/os-release
TimeoutStartSec=0
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/docker pull bugroger/coreos-nvidia-driver:\${VERSION}-$DRIVER_VERSION
ExecStart=/usr/bin/docker run -v /:/rootfs --privileged bugroger/coreos-nvidia-driver:\${VERSION}-$DRIVER_VERSION

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/usr-lib64.mount
[Unit]
After=nvidia-update.service
Requires=nvidia-update.service
ConditionPathExists=/opt/nvidia/.work
Description=Nvidia Kernel Modules

[Mount]
EnvironmentFile=/etc/os-release
Type=overlay
What=overlay
Where=/usr/lib64
Options=lowerdir=/usr/lib64,upperdir=/opt/nvidia/$DRIVER_VERSION/\${VERSION}/lib64,workdir=/opt/nvidia/.work

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/nvidia-persistenced.service
[Unit]
After=nvidia.service
Requires=nvidia.service
Description=NVIDIA Persistence Daemon

[Service]
Type=forking
ExecStart=/opt/bin/nvidia-persistenced --user nvidia-persistenced --persistence-mode --verbose
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/nvidia.service
[Unit]
After=usr-lib64.mount
Requires=usr-lib64.mount
Description=NVIDIA Load

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ldconfig
ExecStart=/usr/sbin/depmod -a
ExecStart=/opt/bin/nvidia-modprobe -u -m -c 0
ExecStart=/opt/bin/nvidia-smi

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/udev/rules.d/01-nvidia.rules
SUBSYSTEM=="pci", ATTRS{vendor}=="0x10de", DRIVERS=="nvidia", TAG+="seat", TAG+="master-of-seat"
EOF
udevadm control --reload-rules

useradd -c "NVIDIA Persistence Daemon" --shell /sbin/nologin --home-dir / nvidia-persistenced || true

systemctl daemon-reload
systemctl enable nvidia-update
systemctl enable usr-lib64.mount
systemctl enable nvidia
systemctl enable nvidia-persistenced
