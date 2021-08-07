#!/bin/bash
set -euxo pipefail

# NB execute apt-cache madison docker-ce to known the available versions.
docker_version="${1:-20.10.8}"; shift || true

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
docker_version="$(apt-cache madison docker-ce | awk "/$docker_version~/{print \$3}")"
apt-get install -y "docker-ce=$docker_version" "docker-ce-cli=$docker_version" containerd.io
apt-mark hold docker-ce docker-ce-cli

# stop docker and containerd.
systemctl stop docker
systemctl stop containerd

# use the systemd cgroup driver.
# NB by default docker uses the containerd runc runtime.
cgroup_driver='systemd'

# configure containerd.
# see https://kubernetes.io/docs/setup/cri/
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

# configure it.
# see https://kubernetes.io/docs/setup/cri/
cat >/etc/docker/daemon.json <<EOF
{
    "experimental": false,
    "debug": false,
    "exec-opts": [
        "native.cgroupdriver=$cgroup_driver"
    ],
    "features": {
        "buildkit": true
    },
    "log-driver": "journald",
    "labels": [
        "os=linux"
    ],
    "hosts": [
        "fd://",
        "tcp://0.0.0.0:2375"
    ],
    "default-runtime": "runc",
    "containerd": "/run/containerd/containerd.sock"
}
EOF
# start docker without any command line flags as its entirely configured from daemon.json.
install -d /etc/systemd/system/docker.service.d
cat >/etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF
systemctl daemon-reload
systemctl start docker
systemctl cat docker
# validate that docker is using the expected cgroup driver.
docker_cgroup_driver="$(docker info -f '{{.CgroupDriver}}')"
if [ "$docker_cgroup_driver" != "$cgroup_driver" ]; then
    echo "ERROR: Cgroup driver MUST be $cgroup_driver, but its $docker_cgroup_driver"
    exit 1
fi

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
