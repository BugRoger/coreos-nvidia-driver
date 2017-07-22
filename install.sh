#!/bin/sh

set -x

rm /opt/nvidia/current
ln -fs /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/bin/* /opt/bin
ln -fs /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION /opt/nvidia/current
ln -fs /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/lib64/libnvidia-ml.so /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/lib64/libnvidia-ml.so.$DRIVER_VERSION
rm /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/lib64/libEGL.so.$DRIVER_VERSION
chmod u+s /opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/bin/nvidia-modprobe

cat <<EOF > /etc/systemd/system/usr-lib64.mount
[Unit]
Description=Nvidia Kernel Modules
Before=local-fs.target
ConditionPathExists=/opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/lib64
ConditionPathExists=/opt/nvidia/.work

[Mount]
Type=overlay
What=overlay
Where=/usr/lib64
Options=lowerdir=/usr/lib64,upperdir=/opt/nvidia/$DRIVER_VERSION/$COREOS_VERSION/lib64,workdir=/opt/nvidia/.work

[Install]
WantedBy=local-fs.target
EOF

cat <<EOF > /etc/systemd/system/nvidia-persistenced.service
[Unit]
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
Description=NVIDIA Load

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/bin/nvidia-modprobe -u -m -c 0
ExecStart=/opt/bin/nvidia-smi

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/udev/rules.d/01-nvidia.rules
SUBSYSTEM=="pci", ATTRS{vendor}=="0x10de", DRIVERS=="nvidia", TAG+="seat", TAG+="master-of-seat"
EOF

useradd -c "NVIDIA Persistence Daemon" --shell /sbin/nologin --home-dir / nvidia-persistenced

systemctl daemon-reload
systemctl enable usr-lib64.mount
systemctl start usr-lib64.mount

ldconfig
depmod -a
udevadm control --reload-rules

systemctl enable nvidia
systemctl start nvidia

systemctl enable nvidia-persistenced
systemctl start nvidia-persistenced
