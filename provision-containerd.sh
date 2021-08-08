#!/bin/bash
source /vagrant/lib.sh

# NB execute apt-cache madison containerd.io to known the available versions.
containerd_version="${1:-1.4.9}"; shift || true

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# install containerd.
# see https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-repository
apt-get install -y apt-transport-https software-properties-common
wget -qO- https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
containerd_version="$(apt-cache madison containerd.io | awk "/$containerd_version-/{print \$3}")"
apt-get install -y "containerd.io=$containerd_version" patch
apt-mark hold containerd.io

# stop containerd.
systemctl stop containerd

# use the systemd cgroup driver.
# NB by default docker uses the containerd runc runtime.
cgroup_driver='systemd'

# configure containerd.
# see https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
cat >/etc/modules-load.d/containerd.conf <<'EOF'
overlay
br_netfilter
EOF
cat /etc/modules-load.d/containerd.conf | xargs -L1 modprobe
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system
containerd config default >/etc/containerd/config.toml
cp -p /etc/containerd/config.toml{,.orig}
if [ "$cgroup_driver" = 'systemd' ]; then
    patch -d / -p0 </vagrant/containerd-config.toml.patch
else
    patch -d / -R -p0 </vagrant/containerd-config.toml.patch
fi
diff -u /etc/containerd/config.toml{.orig,} || true
systemctl restart containerd
