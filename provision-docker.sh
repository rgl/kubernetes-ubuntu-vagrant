#!/bin/bash
set -eux

# NB execute apt-cache madison docker-ce to known the available versions.
docker_version="${1:-5:18.09.8~3-0~ubuntu-bionic}"; shift || true

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
apt-get install -y "docker-ce=$docker_version" "docker-ce-cli=$docker_version" containerd.io
apt-mark hold docker-ce docker-ce-cli

# configure it.
# see https://kubernetes.io/docs/setup/cri/
# NB by default docker uses the containerd runc runtime.
# NB this uses the cgroupfs driver due to https://github.com/kubernetes/kubernetes/issues/76531
systemctl stop docker
#cgroup_driver='systemd'
cgroup_driver='cgroupfs'
cat >/etc/docker/daemon.json <<EOF
{
    "debug": false,
    "default-runtime": "runc",
    "containerd": "/run/containerd/containerd.sock",
    "exec-opts": [
        "native.cgroupdriver=$cgroup_driver"
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
    sed -i -E 's,^(\s*systemd_cgroup =).*,\1 true,' /etc/containerd/config.toml
else
    sed -i -E 's,^(\s*systemd_cgroup =).*,\1 false,' /etc/containerd/config.toml
fi
diff -u /etc/containerd/config.toml{.orig,} || true
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
