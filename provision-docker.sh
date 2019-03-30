#!/bin/bash
set -eux

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# install docker.
# see https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-repository
apt-get install -y apt-transport-https software-properties-common
wget -qO- https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# configure it.
# see https://kubernetes.io/docs/setup/cri/
systemctl stop docker
cat >/etc/docker/daemon.json <<'EOF'
{
    "debug": false,
    "exec-opts": [
        "native.cgroupdriver=systemd"
    ],
    "labels": [
        "os=linux"
    ],
    "hosts": [
        "fd://",
        "tcp://0.0.0.0:2375"
    ]
}
EOF
sed -i -E 's,^(ExecStart=/usr/bin/dockerd).*,\1,' /lib/systemd/system/docker.service
systemctl daemon-reload
systemctl start docker

# configure containerd.
# see https://kubernetes.io/docs/setup/cri/
cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system
containerd config default >/etc/containerd/config.toml
sed -i -E 's,^(\s*systemd_cgroup =).*,\1 true,' /etc/containerd/config.toml
systemctl restart containerd

# let the vagrant user manage docker.
usermod -aG docker vagrant

# kick the tires.
docker version
docker info
docker network ls
ip link
bridge link
docker run --rm hello-world
docker run --rm alpine cat /etc/resolv.conf
docker run --rm alpine ping -c1 8.8.8.8
